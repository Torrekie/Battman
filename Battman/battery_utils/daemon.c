// Avoid libiosexec
#ifndef LIBIOSEXEC_INTERNAL
#define LIBIOSEXEC_INTERNAL 1
#endif
#ifdef posix_spawn
#undef posix_spawn
#endif
#define LIBIOSEXEC_H

#include "../common.h"
#include "../iokitextern.h"
#include "libsmc.h"
#include <CoreFoundation/CFDictionary.h>
#include <CoreFoundation/CFNumber.h>
#include <CoreFoundation/CFString.h>
#include <errno.h>
#include <fcntl.h>
#include <mach-o/dyld.h>
#include <pthread.h>
#include <spawn.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <unistd.h>
#include <pwd.h>
#include <notify.h>

#if __has_include(<spawn_private.h>)
#include <spawn_private.h>
#else
extern int posix_spawnattr_set_persona_np(const posix_spawnattr_t *__restrict, uid_t, uint32_t);
extern int posix_spawnattr_set_persona_uid_np(const posix_spawnattr_t *__restrict, uid_t);
extern int posix_spawnattr_set_persona_gid_np(const posix_spawnattr_t *__restrict, uid_t);
extern int posix_spawnattr_setprocesstype_np(posix_spawnattr_t *, int);
extern int posix_spawnattr_setjetsam_ext(posix_spawnattr_t *, int, int, int, int);
#endif

extern char **environ;

extern void subscribeToPowerEvents(void (*cb)(int, io_registry_entry_t, int32_t));

struct battman_daemon_settings {
	unsigned char enable_charging_at_level;
	unsigned char disable_charging_at_level;
	unsigned char drain_config;
};

static struct battman_daemon_settings *daemon_settings;
static int CH0ICache = -1;
static int CH0CCache = -1;
static int last_power_level = -1;
static char daemon_settings_path[1024];

static void update_power_level(int);

static void daemon_control_thread(int fd) {
	// XXX: Consider use XPC or dispatch?
	while (1) {
		char cmd;
		if (read(fd, &cmd, 1) <= 0) {
			NSLog(CFSTR("Daemon: Closing bc %s"), strerror(errno));
			close(fd);
			set_badge(NULL);
			return;
		}
		NSLog(CFSTR("Daemon: READ cmd %d"), (int)cmd);
		if (cmd == 3) {
			char val = 0;
			smc_write_safe('CH0I', &val, 1);
			smc_write_safe('CH0C', &val, 1);
			write(fd, &cmd, 1);
			close(fd);
			set_badge(NULL);
			exit(0);
		} else if (cmd == 2) {
			write(fd, &cmd, 1);
		} else if (cmd == 4) {
			update_power_level(last_power_level);
		} else if (cmd == 5) {
			close(fd);
			set_badge(NULL);
			pthread_exit(NULL);
		} else if (cmd == 6) {
			// Redirect logs
			// Will stop responding to commands
			const char *connMsg = "Hello from daemon! Log redirection started!\n";
			write(fd, connMsg, strlen(connMsg));
			int pipefds[2];
			pipe(pipefds);
			dup2(pipefds[1], 1);
			dup2(pipefds[1], 2);
			close(pipefds[1]);
			int devnull = open("/dev/null", O_WRONLY);
			char buf[512];
			while (1) {
				ssize_t len = read(pipefds[0], buf, 512);
				if (len <= 0) {
					close(fd);
					dup2(devnull, 1);
					dup2(devnull, 2);
					close(devnull);
					close(pipefds[0]);
					pthread_exit(NULL);
				}
				if (write(fd, buf, len) <= 0) {
					dup2(devnull, 1);
					dup2(devnull, 2);
					close(devnull);
					close(pipefds[0]);
					pthread_exit(NULL);
				}
			}
		}
	}
}

static void daemon_control() {
	struct sockaddr_un sockaddr;
	sockaddr.sun_family = AF_UNIX;
	
	const char *socket_path = battman_socket_path();
	strncpy(sockaddr.sun_path, socket_path, sizeof(sockaddr.sun_path) - 1);
	sockaddr.sun_path[sizeof(sockaddr.sun_path) - 1] = '\0';
	
	remove(sockaddr.sun_path);
	umask(0);
	int sock = socket(AF_UNIX, SOCK_STREAM, 0);
	if (bind(sock, (struct sockaddr *)&sockaddr, sizeof(struct sockaddr_un)) != 0)
		abort();
	int trueVal = 1;
	setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &trueVal, 4);
	if (listen(sock, 3) != 0)
		abort();
	while (1) {
		int conn = accept(sock, NULL, NULL);
		if (conn == -1)
			continue;
		pthread_t ct;
		pthread_create(&ct, NULL, (void *(*)(void *))daemon_control_thread, (void *)(uint64_t)conn);
		pthread_detach(ct);
	}
}

// The safest approach to change OBC settings, at least iOS 16
static int obc_switch(bool on) {
	struct passwd *pw = getpwnam("mobile");
	if (!pw)
		return 1;

	uid_t orig_euid = geteuid();
	gid_t orig_egid = getegid();

	// Required: drop to mobile for the write (so CFPreferences writes to /var/mobile/Library/Preferences)
	if (setegid(pw->pw_gid) != 0 || seteuid(pw->pw_uid) != 0) {
		perror("failed to switch to mobile");
		return 1;
	}

	CFStringRef domain = CFSTR("com.apple.smartcharging.topoffprotection");
	CFStringRef key = CFSTR("enabled");
	CFNumberRef value = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &on);

	CFPreferencesSetValue(key, value, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
	CFRelease(value);
	if (!CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)) {
		CFPreferencesAppSynchronize(domain);
	}

	// Tell CoreDuet/PowerUI we changed the settings
	notify_post("com.apple.smartcharging.defaultschanged");

	// restore
	if (seteuid(orig_euid) != 0 || setegid(orig_egid) != 0) {
		perror("failed to restore euid/egid");
	}

	return 0;
}

/* 6 keys we had to notice
   CH0C: Battery charge control (But not affecting AC)
   CH0B: Managed charging control
   CH0I: AC control
   CH0J: Managed AC control
   CH0K: Managed AC control
   CH0R: Inflow inhibit flags
   When CH0B is set, CH0C and CH0B will be marked with 0010, which typically means the battery charge control has been taken over.
   When CH0J is set, CH0I and CH0J will be marked with 0x20, which typically means the AC control has been taken over.
   CH0B/CH0J/CH0K is typically used by OBC, normally we should avoid operating with these keys, since OBC should be controlled by user but not us. But we still provide options to let users override the OBC behavior.
   CH0R is controlled by BMS, the only condition we had to notice is low flag 1 (0010), which typically means no AC power provided. We should avoid writing keys when this flag matched.
 */

static void power_switch_safe(bool on, bool override_obc, bool keep_ac) {
	uint8_t ret1 = 0;
	/* ExternalConnected also refers to inflow state */
	smc_read_n('CHCE', &ret1, sizeof(ret1));
	if (!ret1) {
		set_badge("⊗"); // No adapter connected
		return;
	}

	uint32_t ret4 = 0;
	smc_read_n('CH0R', &ret4, sizeof(ret4));
	/* Bit 1: No VBUS */
	if (ret4 & (1 << 1)) {
		set_badge("⏻"); // Stopped for some reason
		return;
	}

	// keep_ac should only be set when drain unset
	ret1 = 0;
	bool obc_taken = false;
	if (keep_ac) {
		NSLog(CFSTR("Daemon setting CH0C %s"), on ? "on" : "off");
		smc_read_n('CH0C', &ret1, sizeof(ret1));
		/* Bit 0: On/Off (setbatt) */
		/* Bit 1: OBC or no VBUS */
		if (ret1 & (1 << 1)) {
			if (override_obc) {
				obc_switch(false);
				smc_write_safe('CH0B', &on, 1);
			} else {
				obc_taken = true;
			}
		}
		/* No need to keep other bits when setting, BMS is automatically doing it */
		if (on != CH0CCache) {
			CH0CCache = on;
			smc_write_safe('CH0C', &on, 1);
		}
	} else {
		NSLog(CFSTR("Daemon setting CH0I %s"), on ? "on" : "off");
		/* Bit 0: On/Off (Inhibit inflow) */
		/* Bit 1: OBC or no VBUS */
		/* Bit 5: Field Diagnostics */
		// Otherwise, just cut off AC to stop charging
		smc_read_n('CH0I', &ret1, sizeof(ret1));
		if (ret1 & (1 << 1)) {
			if (override_obc)
				obc_switch(false);
			else
				obc_taken = true;
			// Do not explicitly set CH0J, it will add Bit 5 instead of Bit 1
			// Resulting in NOT_CHARGING_REASON_FIELDDIAGS
			// smc_write_safe('CH0J', &on, 1);
		}
		/* No need to keep other bits when setting, BMS is automatically doing it */
		if (on != CH0ICache) {
			CH0ICache = on;
			smc_write_safe('CH0I', &on, 1);
		}
	}
	if (obc_taken)
		set_badge("⎋"); // OBC taken
	else
		set_badge(on ? "▶" : "⏾"); // Charging On/Off state
}

static void update_power_level(int val) {
	if (val == -1)
		return;
	last_power_level = val;

	char keep_ac = BIT_GET(daemon_settings->drain_config, 0);
	char override_obc = BIT_GET(daemon_settings->drain_config, 1);

	if (daemon_settings->enable_charging_at_level != 255) {
		if (val <= daemon_settings->enable_charging_at_level) {
			val = 0; // Enable
		} else if (val >= daemon_settings->disable_charging_at_level) {
			val = 1; // Disable
		}
	} else if (daemon_settings->disable_charging_at_level != 255) {
		val = (val >= daemon_settings->disable_charging_at_level);
	}

	return power_switch_safe(val, override_obc, keep_ac);
}

static void powerevent_listener(int a, io_registry_entry_t b, int32_t c) {
	// kIOPMMessageBatteryStatusHasChanged
	if (c != -536723200)
		return;

	if (access(daemon_settings_path, F_OK) == -1) {
		// Quit when app removed or daemon no longer needed
		exit(0);
	}
	// XXX: Guards?
	CFNumberRef capacity = IORegistryEntryCreateCFProperty(b, CFSTR("CurrentCapacity"), 0, 0);
	int val;
	CFNumberGetValue(capacity, kCFNumberIntType, &val);
	CFRelease(capacity);
	update_power_level(val);
}

void daemon_main(void) {
	signal(SIGPIPE, SIG_IGN);
	char *end = stpcpy(stpcpy(daemon_settings_path, battman_config_dir()), "/daemon");
	strcpy(end, ".run");
	int runfd = open(daemon_settings_path, O_RDWR | O_CREAT, 0666);
	pid_t pid = getpid();
	write(runfd, &pid, 4);
	close(runfd);
	strcpy(end, "_settings");
	int settingsfd = open(daemon_settings_path, O_RDONLY);
	if (settingsfd == -1)
		exit(0); // Not enabled
	daemon_settings = mmap(NULL, sizeof(struct battman_daemon_settings), PROT_READ, MAP_SHARED, settingsfd, 0);
	if (!daemon_settings)
		exit(0);
	close(settingsfd);
	smc_open();
	// FIXME: Implement standalone listeners for daemon
	subscribeToPowerEvents(powerevent_listener);
	pthread_t tmp;
	pthread_create(&tmp, NULL, (void *(*)(void *))daemon_control, NULL);
	pthread_join(tmp, NULL);
}

int battman_run_daemon(void) {
	posix_spawnattr_t sattr;
	posix_spawnattr_init(&sattr);
	posix_spawnattr_set_persona_np(&sattr, 99, 1); // POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE
	posix_spawnattr_set_persona_uid_np(&sattr, 0);
	posix_spawnattr_set_persona_gid_np(&sattr, 0);
	posix_spawnattr_setprocesstype_np(&sattr, 0x300); // daemon standard
	// JETSAM_PRIORITY_IMPORTANT(18) or JETSAM_PRIORITY_BACKGROUND(3)?
	// FIXME: Consider add a toggle for it
	int priority = 18;
	if (__builtin_available(iOS 16.0, *)) {
		priority = 180;
	}
	// XXX: Consider force to UI role, since this was not a real launchdaemon
	// posix_spawnattr_set_darwin_role_np(&attr, PRIO_DARWIN_ROLE_UI);

	// Limit 80 MiB
	posix_spawnattr_setjetsam_ext(&sattr, 0, priority, 80, 80);
#ifndef POSIX_SPAWN_SETSID
#define POSIX_SPAWN_SETSID 0x400
#endif
	posix_spawnattr_setflags(&sattr, POSIX_SPAWN_SETSID);
	char executable[1024];
	uint32_t size = 1024;
	_NSGetExecutablePath(executable, &size);
	char *newargv[] = {executable, "--daemon", NULL};
	pid_t dpid;
	int err = posix_spawn(&dpid, executable, NULL, &sattr, (char **)newargv, environ);
	if (err != 0) {
		show_alert(L_ERR, strerror(err), L_OK);
	}
	posix_spawnattr_destroy(&sattr);
	return dpid;
}
