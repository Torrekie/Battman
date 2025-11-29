// Avoid libiosexec
#ifndef LIBIOSEXEC_INTERNAL
#define LIBIOSEXEC_INTERNAL 1
#endif
#ifdef posix_spawn
#undef posix_spawn
#endif
#define LIBIOSEXEC_H

#include <CoreFoundation/CFString.h>
#include <CoreFoundation/CFNumber.h>
#include <CoreFoundation/CFPreferences.h>
#include <errno.h>
#include <mach-o/dyld.h>
#include <pthread.h>
#include <signal.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "../common.h"
#include "../intlextern.h"

extern int posix_spawnattr_set_persona_np(const posix_spawnattr_t *__restrict, uid_t, uint32_t);
extern int posix_spawnattr_set_persona_uid_np(const posix_spawnattr_t *__restrict, uid_t);
extern int posix_spawnattr_set_persona_gid_np(const posix_spawnattr_t *__restrict, uid_t);

extern char **environ;

static int worker_pipefd[2];
static pid_t worker_pid = 0;

extern void NSLog(CFStringRef,...);

// Quits when parent quits
static void parent_monitor() {
	while (1) {
		if (getppid() == 1) {
			close(worker_pipefd[0]);
			close(worker_pipefd[1]);
			exit(0);
		}
		sleep(10);
	}
}

void battman_run_worker(const char *pipedata) {
	pthread_t t;
	pthread_create(&t, NULL, (void *(*)(void *))parent_monitor, NULL);
	pthread_detach(t);
	*(int64_t *)worker_pipefd = atoll(pipedata);
	CFStringRef bs_suite_name, bs_suite_name_bri = NULL;

	if (__builtin_available(iOS 16.0, macOS 13.0, *)) {
		bs_suite_name = CFSTR("com.apple.powerd.lowpowermode");
	} else if (__builtin_available(iOS 15.0, macOS 12.0, *)) {
		bs_suite_name = CFSTR("com.apple.powerd.lowpowermode");
		bs_suite_name_bri = CFSTR("com.apple.coreduetd.batterysaver"); // Special case
	} else {
		// Even this process is designed for iOS 15+, we still need to fallbacks for some curious users
		setgid(501);
		setuid(501);
		bs_suite_name = CFSTR("com.apple.coreduetd.batterysaver");
	}
	if (!bs_suite_name_bri)
		bs_suite_name_bri = bs_suite_name;

	while (1) {
		char cmd;
		if (read(worker_pipefd[0], &cmd, 1) != 1) {
			close(worker_pipefd[0]);
			close(worker_pipefd[1]);
			exit(0);
		}
		if (cmd == 0) {
			// END
			close(worker_pipefd[0]);
			close(worker_pipefd[1]);
			exit(0);
		} else if (cmd == 1) {
			// set autoDisableWhenPluggedIn
			char val;
			read(worker_pipefd[0], &val, 1);
			CFPreferencesSetAppValue(CFSTR("autoDisableWhenPluggedIn"),val?kCFBooleanTrue:kCFBooleanFalse,bs_suite_name);
			CFPreferencesAppSynchronize(bs_suite_name);
			val = 1;
			write(worker_pipefd[1], &val, 1);
			continue;
		} else if (cmd == 2) {
			// set allow autodisablethreshold
			char val;
			read(worker_pipefd[0], &val, 1);
			const double double80=80;
			CFNumberRef num=val?CFNumberCreate(0,kCFNumberDoubleType,(const void*)&double80):NULL;
			CFPreferencesSetAppValue(CFSTR("autoDisableThreshold"),num,bs_suite_name);
			if(num)
				CFRelease(num);
			CFPreferencesAppSynchronize(bs_suite_name);
			val = 1;
			write(worker_pipefd[1], &val, 1);
			continue;
		} else if (cmd == 3) {
			// set autodisablethreshold
			float val;
			read(worker_pipefd[0], &val, 4);
			CFNumberRef num=CFNumberCreate(0,kCFNumberFloat32Type,(const void*)&val);
			CFPreferencesSetAppValue(CFSTR("autoDisableThreshold"),num,bs_suite_name);
			CFRelease(num);
			CFPreferencesAppSynchronize(bs_suite_name);
			char retval = 1;
			write(worker_pipefd[1], &retval, 1);
			continue;
		} else if (cmd == 4) {
			// get all
			char buf[6];
			CFNumberRef thr=CFPreferencesCopyAppValue(CFSTR("autoDisableThreshold"),bs_suite_name);
			buf[4] = thr ? 1 : 0;
			if(thr) {
				CFNumberGetValue(thr,kCFNumberFloat32Type,(void*)buf);
				CFRelease(thr);
			}else{
				*(float *)buf = 80;
			}
			buf[5] = CFPreferencesGetAppBooleanValue(CFSTR("autoDisableWhenPluggedIn"),bs_suite_name,NULL);
			char retval = 2;
			write(worker_pipefd[1], &retval, 1);
			write(worker_pipefd[1], buf, 6);
			continue;
		} else if (cmd == 5) {
			// thermtune bool
			uint16_t val;
			char buf[6];
			read(worker_pipefd[0], &val, 2);
			int ret = 1001;
			int sect = (val & 0xF000) >> 12;
			int row = (val & 0x0F00) >> 8;
			// TODO: Reduce redundant code
			switch (sect) {
				case 1: {
					// TT_SECT_GENERAL
					switch (row) {
						case 0: {
							// TT_ROW_GENERAL_ENABLED
							extern int setOSNotifEnabled(bool enable, bool persist);
							ret = setOSNotifEnabled((val & 1), (val & 2) != 0);
							break;
						}
						case 1: {
							// TT_ROW_GENERAL_CLTM
							extern int setCLTMEnabled(bool enable, bool persist);
							ret = setCLTMEnabled((val & 1), (val & 2) != 0);
							break;
						}
					}
					break;
				}
				case 2: {
					// TT_SECT_HIP
					switch (row) {
						case 0: {
							// TT_ROW_HIP_ENABLED
							extern int setHIPEnabled(bool enable, bool persist);
							ret = setHIPEnabled((val & 1), (val & 2) != 0);
							break;
						}
						case 1: {
							// TT_ROW_HIP_SIMULATE
							extern int setSimulateHIPEnabled(bool enable, bool persist);
							ret = setSimulateHIPEnabled((val & 1), 0);
							break;
						}
					}
					break;
				}
				case 3: {
					// TT_SECT_SUNLIGHT
					switch (row) {
						case 0: {
							// TT_ROW_SUNLIGHT_AUTO
							extern bool delSunlightEntry(void);
							extern int setSunlightEnabled(bool enable, bool persist);
							if (val & 1) ret = delSunlightEntry();
							else ret = setSunlightEnabled(0, 0);
							break;
						}
						case 1: {
							// TT_ROW_SUNLIGHT_SIMULATE
							extern int setSunlightEnabled(bool enable, bool persist);
							ret = setSunlightEnabled((val & 1), (val & 2) != 0);
							break;
						}
					}
					break;
				}
				case 4: {
					// TT_SECT_LEVEL
					switch (row) {
						case 0: {
							// TT_ROW_LEVEL_PRESSURE
							extern int set_thermal_pressure(int pressure);
							ret = set_thermal_pressure(val & 0xFF);
							break;
						}
						case 1: {
							// TT_ROW_LEVEL_NOTIF
							extern int set_thermal_notif_level(int level);
							ret = set_thermal_notif_level(val & 0xFF);
							break;
						}
					}
					break;
				}
			}
			*(int *)buf = ret;
			char retval = 2;
			write(worker_pipefd[1], &retval, 1);
			write(worker_pipefd[1], buf, 6);
			continue;
		} else if (cmd == 6) {
			// get backlight reduction
			char buf[6];
			CFNumberRef val = CFPreferencesCopyAppValue(CFSTR("backlightReduction"), bs_suite_name);
			buf[4] = val ? 1 : 0;
			if (val) {
				CFNumberGetValue(val, kCFNumberFloat32Type,(void *)buf);
				CFRelease(val);
			} else {
				*(float *)buf = 20;
			}
			char retval = 2;
			write(worker_pipefd[1], &retval, 1);
			write(worker_pipefd[1], buf, 6);
			continue;
		} else if (cmd == 7) {
			// set backlight reduction
			// set autodisablethreshold
			float val;
			read(worker_pipefd[0], &val, 4);
			CFNumberRef num = CFNumberCreate(0, kCFNumberFloat32Type, (const void *)&val);
			CFPreferencesSetAppValue(CFSTR("backlightReduction"), num, bs_suite_name_bri);
			CFRelease(num);
			CFPreferencesAppSynchronize(bs_suite_name_bri);
			char retval = 1;
			write(worker_pipefd[1], &retval, 1);
			continue;
		}
	}
}

static void battman_spawn_worker() {
	// posix_spawn_file_actions_t file_actions;
	// posix_spawn_file_actions_init(&file_actions);
	int outfdg[2];
	pipe(outfdg);
	pipe(worker_pipefd);
	int tmp = worker_pipefd[1];
	worker_pipefd[1] = outfdg[1];
	outfdg[1] = tmp;
	// posix_spawn_file_actions_adddup2(&file_actions,worker_pipefd[0],0);
	// posix_spawn_file_actions_adddup2(&file_actions,worker_pipefd[1],2);
	posix_spawnattr_t spawnattr = NULL;
	posix_spawnattr_init(&spawnattr);
	posix_spawnattr_set_persona_np(&spawnattr, 99, 1);
	posix_spawnattr_set_persona_uid_np(&spawnattr, 0);
	posix_spawnattr_set_persona_gid_np(&spawnattr, 0);
	char executable[1024];
	uint32_t size = 1024;
	_NSGetExecutablePath(executable, &size);
	char pipedata[16];
	sprintf(pipedata, "%lld", *(int64_t *)outfdg);
	char *newargv[] = {executable, "--worker", pipedata, NULL};
	int err = posix_spawn(&worker_pid, executable, NULL, &spawnattr, (char **)newargv, environ);
	if (err != 0) {
		NSLog(CFSTR("POSIX spawn failed: %s"), strerror(err));
		char *str = malloc(1024);
		sprintf(str, "%s: %s", _C("Helper failed to launch"), strerror(err));
		//if (is_carbon())
		//	show_alert(L_FAILED, str, L_OK);
		free(str);
		return;
	}
	close(outfdg[0]);
	close(outfdg[1]);
	posix_spawnattr_destroy(&spawnattr);
	// posix_spawn_file_actions_destroy(&file_actions);
	return;
}

void worker_test(void) {
	battman_spawn_worker();
	// char buf[10];
	// read(worker_pipefd[0],buf,10);
	// NSLog(@"buf=%s\n",buf);
	close(worker_pipefd[1]);
	close(worker_pipefd[0]);
}

// Non MT-safe, only call from main thread
uint64_t battman_worker_call(char cmd, void *arg, uint64_t arglen) {
	if (worker_pid == 0 || (kill(worker_pid, 0) == -1 && errno == ESRCH)) {
		if (worker_pid) {
			close(worker_pipefd[0]);
			close(worker_pipefd[1]);
		}
		battman_spawn_worker();
	}
	write(worker_pipefd[1], &cmd, 1);
	if (arglen)
		write(worker_pipefd[1], arg, arglen);
	if (cmd == 0) {
		close(worker_pipefd[0]);
		close(worker_pipefd[1]);
		return 0;
	}
	char retval;
	read(worker_pipefd[0], &retval, 1);
	// NSLog(@"RETVAL=%d",(int)retval);
	if (retval == 2) {
		uint64_t data = 0;
		read(worker_pipefd[0], &data, 6);
		return data;
	}
	return 0;
}

void battman_worker_oneshot(char cmd, char arg) { battman_worker_call(cmd, &arg, 1); }
