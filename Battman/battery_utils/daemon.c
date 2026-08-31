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
#include "../intlextern.h"
#include "libsmc.h"
#include <CoreFoundation/CFDictionary.h>
#include <CoreFoundation/CFNumber.h>
#include <CoreFoundation/CFString.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <mach-o/dyld.h>
#include <pthread.h>
#include <spawn.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/un.h>
#include <unistd.h>
#include <pwd.h>
#include <notify.h>

#if __has_include(<spawn_private.h>)
#include <spawn_private.h>
#else
extern int posix_spawnattr_set_persona_np(const posix_spawnattr_t *__restrict, uid_t, uint32_t);
extern int posix_spawnattr_set_persona_uid_np(const posix_spawnattr_t *__restrict, uid_t);
extern int posix_spawnattr_set_persona_gid_np(const posix_spawnattr_t *__restrict, gid_t);
extern int posix_spawnattr_setprocesstype_np(posix_spawnattr_t *, int);
extern int posix_spawnattr_setjetsam_ext(posix_spawnattr_t *, short, int, int, int);
#endif

#ifndef POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE
#define POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE 0x1
#endif

#ifndef POSIX_SPAWN_PROC_TYPE_DAEMON_STANDARD
#define POSIX_SPAWN_PROC_TYPE_DAEMON_STANDARD 0x00000300
#endif

#ifndef POSIX_SPAWN_SETSID
#define POSIX_SPAWN_SETSID 0x0400
#endif

#define BATTMAN_ROOT_PERSONA_ID 99
#define BATTMAN_JETSAM_PRIORITY_IMPORTANT_OLD 18
#define BATTMAN_JETSAM_PRIORITY_IMPORTANT_NEW 180
#define BATTMAN_DAEMON_MEMLIMIT_MIB 80

extern char **environ;

extern void subscribeToPowerEvents(void (*cb)(int, io_registry_entry_t, int32_t));

struct battman_daemon_settings {
	unsigned char enable_charging_at_level;
	unsigned char disable_charging_at_level;
	unsigned char drain_config;
};

_Static_assert(sizeof(struct battman_daemon_settings) == BATTMAN_DAEMON_SETTINGS_SIZE,
	               "daemon settings layout must match the client mapping");

static bool daemon_settings_valid(const struct battman_daemon_settings *settings) {
	if (!settings)
		return false;
	bool levels_valid = (settings->enable_charging_at_level == 255 ||
		        settings->enable_charging_at_level <= 100) &&
		       (settings->disable_charging_at_level == 255 ||
		        settings->disable_charging_at_level <= 100);
	if (!levels_valid)
		return false;
	/* A limit-only configuration uses 255 for the resume threshold.  Reject
	 * the inverse (resume set, limit unset), because the transition logic would
	 * otherwise pass a raw percentage to power_switch_safe as an inhibit bit. */
	if (settings->enable_charging_at_level != 255 &&
	    settings->disable_charging_at_level == 255)
		return false;
	if (settings->enable_charging_at_level != 255 &&
	    settings->disable_charging_at_level != 255 &&
	    settings->enable_charging_at_level >= settings->disable_charging_at_level)
		return false;
	return true;
}

static struct battman_daemon_settings *daemon_settings;
/* Held for the daemon lifetime so a second instance cannot pass the PID-file
 * check while this process is still serving the socket. */
static int daemon_run_fd = -1;
static int CH0ICache = -1;
static int CH0CCache = -1;
static int last_power_level = -1;
static char daemon_settings_path[1024];
static int8_t last_charging_port = -1; // Track last known charging port to detect transitions
#define BATTMAN_MAX_CONTROL_CLIENTS 8
static pthread_mutex_t daemon_client_count_lock = PTHREAD_MUTEX_INITIALIZER;
static unsigned int daemon_client_count;

static void update_power_level(int);

static int battman_daemon_jetsam_priority(void) {
	// XNU 8020/iOS 15 uses the old compact band shape; newer kernels use the scaled shape.
	if (__builtin_available(iOS 16.0, *))
		return BATTMAN_JETSAM_PRIORITY_IMPORTANT_NEW;
	return BATTMAN_JETSAM_PRIORITY_IMPORTANT_OLD;
}

static bool daemon_unlink_locked_run_path(const char *path, int locked_fd,
	                                          bool *did_unlink);
static bool daemon_mark_run_stopping(int fd);

static void cleanup_daemon_files(bool remove_settings) {
	char cleanup_path[PATH_MAX];
	/* Release the advisory lock only after the pathname cleanup.  Keeping this
	 * descriptor open for the daemon lifetime prevents a second launcher from
	 * racing the PID file, while closing it here also avoids a descriptor leak
	 * on the unsupported-SMC/normal-exit paths. */
	int held_run_fd = daemon_run_fd;
	daemon_run_fd = -1;
	const char *config_dir = battman_config_dir();
	if (!config_dir) {
		if (held_run_fd >= 0)
			close(held_run_fd);
		return;
	}
	int length = snprintf(cleanup_path, sizeof(cleanup_path), "%s/daemon.run", config_dir);
	if (length <= 0 || (size_t)length >= sizeof(cleanup_path)) {
		if (held_run_fd >= 0)
			close(held_run_fd);
		return;
	}
	bool removed_run_path = false;
	/* Publish a non-live marker while the run-file lock is still held.  A
	 * launcher that already opened this inode can then recognize an intentional
	 * shutdown after it acquires the lock instead of observing our still-live PID
	 * in the short interval before exit and abandoning a restart. */
	bool marked_stopping = held_run_fd >= 0 && daemon_mark_run_stopping(held_run_fd);
	if (marked_stopping &&
	    daemon_unlink_locked_run_path(cleanup_path, held_run_fd, &removed_run_path) &&
	    removed_run_path) {
		NSLog(CFSTR("Daemon: Cleaned up PID file"));
	}
	if (remove_settings) {
		length = snprintf(cleanup_path, sizeof(cleanup_path), "%s/daemon_settings", config_dir);
		if (length > 0 && (size_t)length < sizeof(cleanup_path) && unlink(cleanup_path) == 0) {
			NSLog(CFSTR("Daemon: Cleaned up settings file"));
		}
	}
	/* Leave the socket node for the next daemon instance to remove immediately
	 * before bind while it owns the run-file lock.  Unlinking it here after the
	 * run pathname was removed would let a replacement daemon publish a new
	 * socket before this cleanup reaches it, causing the old process to delete
	 * the replacement endpoint. */
	if (held_run_fd >= 0)
		close(held_run_fd);
}

static bool daemon_write_all(int fd, const void *buffer, size_t length) {
	if (fd < 0 || (!buffer && length > 0) || length > 4096)
		return false;
	const unsigned char *cursor = (const unsigned char *)buffer;
	while (length) {
		ssize_t count = write(fd, cursor, length);
		if (count < 0 && errno == EINTR)
			continue;
		if (count <= 0)
			return false;
		cursor += (size_t)count;
		length -= (size_t)count;
	}
	return true;
}

static bool daemon_mark_run_stopping(int fd) {
	if (fd < 0)
		return false;
	pid_t stopping_pid = 0;
	size_t written = 0;
	while (written < sizeof(stopping_pid)) {
		ssize_t count = pwrite(fd, ((const unsigned char *)&stopping_pid) + written,
		                       sizeof(stopping_pid) - written, (off_t)written);
		if (count < 0 && errno == EINTR)
			continue;
		if (count <= 0)
			return false;
		written += (size_t)count;
	}
	/* The marker is visible to a waiter immediately; fsync makes it survive a
	 * crash so the next launcher does not mistake the old PID for a live owner. */
	(void)fsync(fd);
	return true;
}

static bool daemon_try_acquire_control_client(void) {
	if (pthread_mutex_lock(&daemon_client_count_lock) != 0)
		return false;
	bool acquired = daemon_client_count < BATTMAN_MAX_CONTROL_CLIENTS;
	if (acquired)
		daemon_client_count++;
	(void)pthread_mutex_unlock(&daemon_client_count_lock);
	return acquired;
}

static void daemon_release_control_client(void) {
	if (pthread_mutex_lock(&daemon_client_count_lock) == 0) {
		if (daemon_client_count > 0)
			daemon_client_count--;
		(void)pthread_mutex_unlock(&daemon_client_count_lock);
	}
}

static void daemon_close_control_client(int fd) {
	if (fd >= 0)
		close(fd);
	daemon_release_control_client();
}

/* bind(2) creates the filesystem socket node, but fchmod/fchown on the socket
 * descriptor itself return EINVAL on Darwin.  Apply access policy to the bound
 * pathname instead.  Revalidate it as a socket before and after each mutation
 * so a concurrent pathname replacement cannot make us chmod/chown an arbitrary
 * file.  The daemon still owns daemon.run while this setup runs, so another
 * cooperative Battman daemon cannot publish a competing endpoint. */
static bool daemon_set_socket_path_permissions(const char *path, gid_t mobile_gid,
	                                            bool has_mobile_group,
	                                            struct stat *owned_stat) {
	if (!path)
		return false;
	errno = 0;
	struct stat before;
	if (lstat(path, &before) != 0 || !S_ISSOCK(before.st_mode) ||
	    before.st_uid != geteuid())
		return false;

	/* Preserve the owner created by bind; only change the group.  If the
	 * pathname is swapped despite the inode checks, this cannot transfer an
	 * attacker's replacement file to root ownership. */
	if (has_mobile_group && lchown(path, (uid_t)-1, mobile_gid) != 0)
		return false;
	struct stat after_owner;
	if (lstat(path, &after_owner) != 0 || !S_ISSOCK(after_owner.st_mode) ||
	    before.st_dev != after_owner.st_dev || before.st_ino != after_owner.st_ino ||
	    after_owner.st_uid != before.st_uid ||
	    (has_mobile_group && after_owner.st_gid != mobile_gid))
		return false;

	if (fchmodat(AT_FDCWD, path, has_mobile_group ? 0660 : 0600,
	             AT_SYMLINK_NOFOLLOW) != 0)
		return false;
	struct stat after_mode;
	if (lstat(path, &after_mode) != 0 || !S_ISSOCK(after_mode.st_mode) ||
	    before.st_dev != after_mode.st_dev || before.st_ino != after_mode.st_ino)
		return false;
	mode_t required = has_mobile_group ? 0660 : 0600;
	bool valid = (after_mode.st_mode & 0777) == required &&
	             (!has_mobile_group || after_mode.st_gid == mobile_gid);
	if (valid && owned_stat)
		*owned_stat = after_mode;
	return valid;
}

static bool daemon_remove_stale_socket_path(const char *path) {
	if (!path)
		return false;
	struct stat st;
	if (lstat(path, &st) != 0)
		return errno == ENOENT;
	/* Never turn daemon startup into an arbitrary-file deletion primitive.  A
	 * previous Battman endpoint is a filesystem socket; any other node requires
	 * explicit user cleanup instead of being silently removed by a root daemon. */
	if (!S_ISSOCK(st.st_mode)) {
		errno = EEXIST;
		return false;
	}
	return unlink(path) == 0 || errno == ENOENT;
}

/*
 * The run file is replaced with a freshly linked inode during startup.  A
 * second launcher may still hold an fd for the old inode while it waits for
 * the write lock.  Never unlink the pathname solely because that old fd is
 * locked: once a replacement has been published, doing so would remove the
 * live daemon's run file.  Call this while locked_fd's write lock is held.
 * Treat an already absent pathname as success so the caller can publish its
 * replacement while retaining the old inode lock as a hand-off guard.
 */
static bool daemon_unlink_locked_run_path(const char *path, int locked_fd,
	                                          bool *did_unlink) {
	if (did_unlink)
		*did_unlink = false;
	if (!path || locked_fd < 0)
		return false;
	struct stat locked_stat;
	if (fstat(locked_fd, &locked_stat) != 0)
		return false;
	struct stat path_stat;
	if (lstat(path, &path_stat) != 0)
		return errno == ENOENT;
	if (locked_stat.st_dev != path_stat.st_dev ||
	    locked_stat.st_ino != path_stat.st_ino)
		return false;
	if (unlink(path) == 0) {
		if (did_unlink)
			*did_unlink = true;
		return true;
	}
	if (errno == ENOENT)
		return true;
	return false;
}

static void *daemon_control_thread(void *context) {
	int fd = (int)(intptr_t)context;
	if (fd < 0)
		return NULL;
	struct timeval timeout = { 2, 0 };
	(void)setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
	(void)setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
#ifdef SO_NOSIGPIPE
	int no_sigpipe = 1;
	(void)setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &no_sigpipe, sizeof(no_sigpipe));
#endif
	int fd_flags = fcntl(fd, F_GETFD, 0);
	if (fd_flags >= 0)
		(void)fcntl(fd, F_SETFD, fd_flags | FD_CLOEXEC);
	// XXX: Consider use XPC or dispatch?
	while (1) {
		char cmd;
		ssize_t read_result;
		do {
			read_result = read(fd, &cmd, 1);
		} while (read_result < 0 && errno == EINTR);
		if (read_result <= 0) {
			NSLog(CFSTR("Daemon: Control client disconnected: %s"), strerror(errno));
			daemon_close_control_client(fd);
			// Client loss during respring is not daemon shutdown; keep files so UI can reconnect.
			return NULL;
		}
		NSLog(CFSTR("Daemon: READ cmd %d"), (int)cmd);
		if (cmd == 3) {
			char val = 0;
			bool restored = smc_write_safe('CH0I', &val, 1) == kIOReturnSuccess &&
			                smc_write_safe('CH0C', &val, 1) == kIOReturnSuccess;
			char response = restored ? cmd : 0;
			(void)daemon_write_all(fd, &response, 1);
			if (!restored) {
				set_badge("?");
				continue;
			}
			daemon_close_control_client(fd);
			set_badge(NULL);
			/* Keep daemon_settings: the UI may still have the shared mapping and
			 * should see the same values when the daemon is started again. */
			cleanup_daemon_files(false);
			exit(0);
		} else if (cmd == 2) {
			(void)daemon_write_all(fd, &cmd, 1);
		} else if (cmd == 4) {
			update_power_level(last_power_level);
		} else if (cmd == 5) {
			daemon_close_control_client(fd);
			return NULL;
		} else if (cmd == 6) {
			// Redirect logs
			// Will stop responding to commands
			const char connMsg[] = "Hello from daemon! Log redirection started!\n";
			if (!daemon_write_all(fd, connMsg, sizeof(connMsg))) {
				daemon_close_control_client(fd);
				return NULL;
			}
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
					daemon_close_control_client(fd);
					dup2(devnull, 1);
					dup2(devnull, 2);
					close(devnull);
					close(pipefds[0]);
					return NULL;
				}
				if (len > 512 || !daemon_write_all(fd, buf, (size_t)len)) {
					daemon_close_control_client(fd);
					dup2(devnull, 1);
					dup2(devnull, 2);
					close(devnull);
					close(pipefds[0]);
					return NULL;
				}
			}
		}
	}
	daemon_close_control_client(fd);
	return NULL;
}

static void *daemon_control(void *context) {
	(void)context;
	struct sockaddr_un sockaddr;
	memset(&sockaddr, 0, sizeof(sockaddr));
	sockaddr.sun_family = AF_UNIX;
	
	const char *socket_path = battman_socket_path();
	if (!socket_path || strlen(socket_path) >= sizeof(sockaddr.sun_path))
			return NULL;
	strncpy(sockaddr.sun_path, socket_path, sizeof(sockaddr.sun_path) - 1);
	sockaddr.sun_path[sizeof(sockaddr.sun_path) - 1] = '\0';
	sockaddr.sun_len = (unsigned char)(offsetof(struct sockaddr_un, sun_path) +
	                                  strlen(sockaddr.sun_path) + 1);
	socklen_t addrlen = (socklen_t)sockaddr.sun_len;
	if (!daemon_remove_stale_socket_path(sockaddr.sun_path)) {
		NSLog(CFSTR("Daemon: Refusing to replace invalid control socket path: %s"), strerror(errno));
		return NULL;
	}
	mode_t previous_umask = umask(077);
	int sock = socket(AF_UNIX, SOCK_STREAM, 0);
	if (sock == -1) {
		umask(previous_umask);
		return NULL;
	}
	int sock_flags = fcntl(sock, F_GETFD, 0);
	if (sock_flags >= 0)
		(void)fcntl(sock, F_SETFD, sock_flags | FD_CLOEXEC);
	if (bind(sock, (struct sockaddr *)&sockaddr, addrlen) != 0) {
		NSLog(CFSTR("Daemon: Failed to bind control socket: %s"), strerror(errno));
		close(sock);
		umask(previous_umask);
		return NULL;
	}
	/* The daemon runs as root while the UI normally runs as mobile. Grant only
	 * that group access; never leave the fallback socket world-writable. Socket
	 * access is controlled by the bound pathname, not by the socket descriptor. */
	struct passwd *mobile = getpwnam("mobile");
	bool mobile_group = mobile != NULL;
	struct stat owned_socket_stat;
	if (!daemon_set_socket_path_permissions(sockaddr.sun_path,
	                                        mobile_group ? mobile->pw_gid : 0,
	                                        mobile_group, &owned_socket_stat)) {
		NSLog(CFSTR("Daemon: Failed to set control socket permissions: %s"), strerror(errno));
		close(sock);
		umask(previous_umask);
		return NULL;
	}
	umask(previous_umask);
	int trueVal = 1;
	(void)setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &trueVal, sizeof(trueVal));
	if (listen(sock, 3) != 0) {
		NSLog(CFSTR("Daemon: Failed to listen on control socket: %s"), strerror(errno));
		close(sock);
		return NULL;
	}
	/* Revalidate immediately before accepting clients.  If a hostile/local
	 * process replaced the pathname after the permission helper, continuing to
	 * serve the now-unlinked socket would leave the UI talking to the replacement
	 * endpoint while this daemon only appears active. */
	struct stat listening_path;
	if (lstat(sockaddr.sun_path, &listening_path) != 0 ||
	    !S_ISSOCK(listening_path.st_mode) ||
	    listening_path.st_dev != owned_socket_stat.st_dev ||
	    listening_path.st_ino != owned_socket_stat.st_ino ||
	    (listening_path.st_mode & 0777) != (mobile_group ? 0660 : 0600) ||
	    (mobile_group && listening_path.st_gid != mobile->pw_gid)) {
		NSLog(CFSTR("Daemon: Control socket path changed during setup"));
		close(sock);
		return NULL;
	}
	while (1) {
		int conn = accept(sock, NULL, NULL);
		if (conn == -1) {
			if (errno == EINTR)
				continue;
			if (errno == EBADF || errno == EINVAL)
				break;
			/* Transient descriptor pressure (EMFILE/ENFILE) and network-stack
			 * interruptions must not turn this loop into a busy spin. */
			usleep(10000);
			continue;
		}
		if (!daemon_try_acquire_control_client()) {
			/* Keep the listener responsive while bounding detached worker memory
			 * and stack consumption. */
			close(conn);
			continue;
		}
		pthread_t ct;
		if (pthread_create(&ct, NULL, daemon_control_thread,
		                   (void *)(intptr_t)conn) != 0) {
			daemon_close_control_client(conn);
			continue;
		}
		pthread_detach(ct);
	}
	close(sock);
	return NULL;
}

// The safest approach to change OBC settings, at least iOS 16
static int obc_switch(bool on) {
	struct passwd *pw = getpwnam("mobile");
	if (!pw)
		return 1;

	uid_t orig_euid = geteuid();
	gid_t orig_egid = getegid();

	// Required: drop to mobile for the write (so CFPreferences writes to /var/mobile/Library/Preferences)
	if (setegid(pw->pw_gid) != 0) {
		perror("failed to switch to mobile");
		return 1;
	}
	if (seteuid(pw->pw_uid) != 0) {
		(void)setegid(orig_egid);
		perror("failed to switch to mobile");
		return 1;
	}

	CFStringRef domain = CFSTR("com.apple.smartcharging.topoffprotection");
	CFStringRef key = CFSTR("enabled");
	int on_value = on ? 1 : 0;
	CFNumberRef value = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &on_value);
	if (!value) {
		(void)seteuid(orig_euid);
		(void)setegid(orig_egid);
		return 1;
	}

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

static void power_switch_safe(bool inhibit_charging, bool override_obc, bool keep_ac) {
	uint8_t ret1 = 0;
	/* ExternalConnected also refers to inflow state */
	if (smc_read_n('CHCE', &ret1, sizeof(ret1)) != kIOReturnSuccess) {
		set_badge("?");
		return;
	}
	if (!ret1) {
		set_badge("⊗"); // No adapter connected
		return;
	}

	uint32_t ret4 = 0;
	if (smc_read_n('CH0R', &ret4, sizeof(ret4)) != kIOReturnSuccess) {
		set_badge("?");
		return;
	}
	/* Bit 1: No VBUS */
	if (ret4 & (1 << 1)) {
		set_badge("⏻"); // Stopped for some reason
		return;
	}

	// keep_ac should only be set when drain unset
	ret1 = 0;
	bool obc_taken = false;
	bool operation_failed = false;
	if (keep_ac) {
		NSLog(CFSTR("Daemon setting CH0C %s"), inhibit_charging ? "inhibit" : "allow");
		if (smc_read_n('CH0C', &ret1, sizeof(ret1)) != kIOReturnSuccess) {
			set_badge("?");
			return;
		}
		/* Bit 0: On/Off (setbatt) */
		/* Bit 1: OBC or no VBUS */
		if (ret1 & (1 << 1)) {
			if (override_obc) {
				if (obc_switch(false) != 0)
					operation_failed = true;
				if (smc_write_safe('CH0B', &inhibit_charging, 1) != kIOReturnSuccess)
					operation_failed = true;
			} else {
				obc_taken = true;
			}
		}
			/* No need to keep other bits when setting, BMS is automatically doing it */
			if (inhibit_charging != CH0CCache) {
				if (smc_write_safe('CH0C', &inhibit_charging, 1) != kIOReturnSuccess)
					operation_failed = true;
				else
					CH0CCache = inhibit_charging;
		}
	} else {
		NSLog(CFSTR("Daemon setting CH0I %s"), inhibit_charging ? "inhibit" : "allow");
		/* Bit 0: On/Off (Inhibit inflow) */
		/* Bit 1: OBC or no VBUS */
		/* Bit 5: Field Diagnostics */
		// Otherwise, just cut off AC to stop charging
		if (smc_read_n('CH0I', &ret1, sizeof(ret1)) != kIOReturnSuccess) {
			set_badge("?");
			return;
		}
		if (ret1 & (1 << 1)) {
			if (override_obc) {
				if (obc_switch(false) != 0)
					operation_failed = true;
			} else {
				obc_taken = true;
			}
			// Do not explicitly set CH0J, it will add Bit 5 instead of Bit 1
			// Resulting in NOT_CHARGING_REASON_FIELDDIAGS
			// smc_write_safe('CH0J', &inhibit_charging, 1);
		}
		/* No need to keep other bits when setting, BMS is automatically doing it */
		if (inhibit_charging != CH0ICache) {
			if (smc_write_safe('CH0I', &inhibit_charging, 1) != kIOReturnSuccess)
				operation_failed = true;
			else
				CH0ICache = inhibit_charging;
		}
	}
	if (operation_failed)
		set_badge("?");
	else if (obc_taken)
		set_badge("⎋"); // OBC taken
	else
		set_badge(inhibit_charging ? "⏾" : "▶"); // Charging allowed/inhibited state
}

static void update_power_level(int val) {
	if (val < 0 || val > 100 || !daemon_settings || !daemon_settings_valid(daemon_settings))
		return;
	/* Both 255 values mean that Battman is not enforcing a threshold. Do not
	 * pass the percentage itself to power_switch_safe (any non-zero value would
	 * otherwise be interpreted as “inhibit”). */
	if (daemon_settings->enable_charging_at_level == 255 &&
	    daemon_settings->disable_charging_at_level == 255) {
		set_badge(NULL);
		last_power_level = val;
		return;
	}

	// Check for wireless charging and show notification when transitioning to wireless
	mach_port_t adapter_family;
	device_info_t adapter_info;
	charging_state_t charging_stat = is_charging(&adapter_family, &adapter_info);
	if (charging_stat > 0 && adapter_info.port == 2 && last_charging_port != 2) {
		// Transitioned to wireless charging (port 2), show notification
		add_notification("com.apple.powerui.lowpowermode",
		                _C("Charging Limit Unavailable"),
		                _C("Wireless Charging Detected"),
		                _C("Charging limit controls are not supported with wireless charging. Use a wired connection for reliable functionality."));
	}
	// Update last known charging port
	last_charging_port = (charging_stat > 0) ? adapter_info.port : -1;

	last_power_level = val;

	char keep_ac = BIT_GET(daemon_settings->drain_config, 0);
	char override_obc = BIT_GET(daemon_settings->drain_config, 1);

	int inhibit_charging = -1;
	if (daemon_settings->enable_charging_at_level != 255) {
		if (val <= daemon_settings->enable_charging_at_level) {
			inhibit_charging = 0; // Enable
		} else if (val >= daemon_settings->disable_charging_at_level) {
			inhibit_charging = 1; // Disable
		} else {
			/* Between the two thresholds, retain the hardware's prior state.  A
			 * raw percentage is not a valid inhibit bit: passing it through would
			 * treat every non-zero midpoint as "inhibit" and defeat hysteresis.
			 * The first ambiguous event is therefore a deliberate no-op. */
			return;
		}
	} else if (daemon_settings->disable_charging_at_level != 255) {
		inhibit_charging = (val >= daemon_settings->disable_charging_at_level);
	} else {
		return;
	}

	power_switch_safe(inhibit_charging, override_obc, keep_ac);
}

static void powerevent_listener(int a, io_registry_entry_t b, int32_t c) {
	(void)a;
	// kIOPMMessageBatteryStatusHasChanged
	if (c != -536723200)
		return;

	if (access(daemon_settings_path, F_OK) == -1) {
		// Quit when app removed or daemon no longer needed
		cleanup_daemon_files(true);
		exit(0);
	}
	// XXX: Guards?
	CFNumberRef capacity = b ? IORegistryEntryCreateCFProperty(b, CFSTR("CurrentCapacity"), 0, 0) : NULL;
	int val = -1;
	if (!capacity || CFGetTypeID(capacity) != CFNumberGetTypeID() ||
	    !CFNumberGetValue(capacity, kCFNumberIntType, &val)) {
		if (capacity)
			CFRelease(capacity);
		return;
	}
	CFRelease(capacity);
	if (val < 0 || val > 100)
		return;
	update_power_level(val);
}

void daemon_main(void) {
	signal(SIGPIPE, SIG_IGN);
	const char *config_dir = battman_config_dir();
	if (!config_dir)
		return;
	char run_path[PATH_MAX];
	int length = snprintf(run_path, sizeof(run_path), "%s/daemon.run", config_dir);
	if (length <= 0 || (size_t)length >= sizeof(run_path))
		return;
	length = snprintf(daemon_settings_path, sizeof(daemon_settings_path),
	                  "%s/daemon_settings", config_dir);
	if (length <= 0 || (size_t)length >= sizeof(daemon_settings_path))
		return;

	// Check for and clean up any stale PID file
	int existing_runfd = open(run_path, O_RDWR | O_NOFOLLOW | O_NONBLOCK);
	if (existing_runfd != -1) {
		struct flock existing_lock = {
			.l_type = F_WRLCK, .l_whence = SEEK_SET, .l_start = 0, .l_len = 0
		};
		if (fcntl(existing_runfd, F_SETLK, &existing_lock) != 0) {
			close(existing_runfd);
			NSLog(CFSTR("Daemon: Existing PID file is locked, another daemon is running"));
			exit(0);
		}
		pid_t old_pid = 0;
		ssize_t bytes = -1;
		/* A creator takes its lock before publishing the PID.  A short bounded
		 * retry still tolerates a legacy instance that left a transient file while
		 * handing off from an older build. */
		for (int attempt = 0; attempt < 10; attempt++) {
			bytes = pread(existing_runfd, &old_pid, sizeof(old_pid), 0);
			if (bytes == (ssize_t)sizeof(old_pid))
				break;
			if (attempt < 9)
				usleep(10000);
		}
		if (bytes == (ssize_t)sizeof(old_pid) && old_pid > 1) {
			int kill_errno = 0;
			if (kill(old_pid, 0) == 0 || (kill_errno = errno) == EPERM) {
				close(existing_runfd);
				// Another daemon might be running.
				NSLog(CFSTR("Daemon: Another daemon (PID %d) appears to be running, exiting"), old_pid);
				exit(0);
			}
			if (kill_errno == ESRCH) {
				// Process does not exist; remove only stale run/socket files.
				NSLog(CFSTR("Daemon: Found stale PID file for dead process %d, cleaning up"), old_pid);
				/* Keep the old inode lock through replacement publication.  A
				 * concurrent launcher may already have an fd for this inode and
				 * acquire the lock after we close it; revalidate its pathname before
				 * allowing that launcher to unlink anything. */
				if (!daemon_unlink_locked_run_path(run_path, existing_runfd, NULL)) {
					close(existing_runfd);
					existing_runfd = -1;
					NSLog(CFSTR("Daemon: Stale PID pathname changed during cleanup, exiting"));
					exit(0);
				}
				/* Leave a stale socket for daemon_control to remove immediately
				 * before bind.  Removing it here after releasing the old run lock
				 * could race a replacement instance and unlink its live endpoint. */
			} else {
				close(existing_runfd);
				NSLog(CFSTR("Daemon: Unable to validate existing PID file, exiting"));
				exit(0);
			}
		} else {
			/* We hold the file's write lock here, so no daemon is in the middle of
			 * publishing its PID.  Reclaim a malformed/short leftover instead of
			 * making every future start fail forever on this stale lock file. */
			/* The lock is still held while removing the malformed entry. Keep
			 * that old inode locked until the replacement is published, and do
			 * not unlink a pathname that has already changed to a new inode. */
			if (!daemon_unlink_locked_run_path(run_path, existing_runfd, NULL)) {
				close(existing_runfd);
				existing_runfd = -1;
				NSLog(CFSTR("Daemon: Incomplete PID pathname changed during cleanup, exiting"));
				exit(0);
			}
			NSLog(CFSTR("Daemon: Removed an incomplete stale PID file"));
		}
	}

	/* Build the PID record in a private, locked inode and publish it with a
	 * non-replacing hard link.  Creating daemon.run directly exposes an empty
	 * pathname: a concurrent launcher could classify that brief window as a
	 * stale file and unlink the first daemon's lock before its PID is written. */
	char temporary_run_path[PATH_MAX];
	int temporary_length = snprintf(temporary_run_path, sizeof(temporary_run_path),
		                              "%s/.daemon.run.%d.XXXXXX", config_dir, (int)getpid());
	if (temporary_length <= 0 || (size_t)temporary_length >= sizeof(temporary_run_path))
		exit(0);
	int runfd = mkstemp(temporary_run_path);
	if (runfd == -1) {
		NSLog(CFSTR("Daemon: Failed to create temporary PID file"));
		exit(0);
	}
	/* Lock the private inode before publishing it. */
	struct flock run_lock = {
		.l_type = F_WRLCK, .l_whence = SEEK_SET, .l_start = 0, .l_len = 0
	};
	if (fcntl(runfd, F_SETLK, &run_lock) != 0) {
		(void)unlink(temporary_run_path);
		close(runfd);
		NSLog(CFSTR("Daemon: Failed to lock PID file, exiting"));
		exit(0);
	}
	/* The daemon is spawned as root, while the UI/Analytics readers normally
	 * run as mobile. Keep the PID non-secret but prevent group/other writes.
	 * fchmod is required because an inherited umask (for example 077) would
	 * otherwise turn the requested 0644 mode into an unreadable 0600 file. */
	if (fchmod(runfd, 0644) != 0) {
		NSLog(CFSTR("Daemon: Failed to set PID file permissions: %s"), strerror(errno));
		(void)daemon_unlink_locked_run_path(temporary_run_path, runfd, NULL);
		close(runfd);
		exit(0);
	}
	/* The lock now protects the complete publication below. */
	pid_t pid = getpid();
	size_t pid_written = 0;
	while (pid_written < sizeof(pid)) {
		ssize_t count = pwrite(runfd, ((const unsigned char *)&pid) + pid_written,
		                       sizeof(pid) - pid_written, (off_t)pid_written);
		if (count < 0 && errno == EINTR)
			continue;
		if (count <= 0)
			break;
		pid_written += (size_t)count;
	}
	if (pid_written != sizeof(pid) || fsync(runfd) != 0) {
		NSLog(CFSTR("Daemon: Failed to publish PID file, exiting"));
		(void)daemon_unlink_locked_run_path(temporary_run_path, runfd, NULL);
		close(runfd);
		exit(0);
	}
	/* link() is atomic and refuses to replace an existing path.  If another
	 * launcher won the name after the stale-file check, leave its record alone
	 * and let this instance exit. */
	if (link(temporary_run_path, run_path) != 0) {
		NSLog(CFSTR("Daemon: Failed to publish PID file: %s"), strerror(errno));
		(void)daemon_unlink_locked_run_path(temporary_run_path, runfd, NULL);
		close(runfd);
		exit(0);
	}
	if (unlink(temporary_run_path) != 0) {
		/* The published hard link is still ours and the lock is held; remove it
		 * before exiting rather than leaving a second hidden pathname behind.
		 * Revalidate the new inode as well, so an external replacement cannot be
		 * removed by this failure path. */
		(void)daemon_unlink_locked_run_path(run_path, runfd, NULL);
		(void)daemon_unlink_locked_run_path(temporary_run_path, runfd, NULL);
		close(runfd);
		exit(0);
	}
	/* Release any old-inode hand-off guard only after the new pathname and PID
	 * record are fully published.  A waiter on the old fd can then revalidate
	 * and observe the replacement instead of unlinking it. */
	if (existing_runfd >= 0) {
		close(existing_runfd);
		existing_runfd = -1;
	}
	daemon_run_fd = runfd;
	NSLog(CFSTR("Daemon: Started with PID %d"), pid);
	int settingsfd = open(daemon_settings_path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK);
	if (settingsfd == -1) {
		cleanup_daemon_files(false); // Keep settings for the next launch
		exit(0); // Not enabled
	}
	struct stat settings_stat;
	if (fstat(settingsfd, &settings_stat) != 0 ||
	    !S_ISREG(settings_stat.st_mode) ||
	    (settings_stat.st_mode & 022) != 0 ||
	    settings_stat.st_size != (off_t)BATTMAN_DAEMON_SETTINGS_SIZE) {
		close(settingsfd);
		cleanup_daemon_files(false); // Keep settings for the next launch
		exit(0);
	}
	daemon_settings = mmap(NULL, BATTMAN_DAEMON_SETTINGS_SIZE,
	                       PROT_READ, MAP_SHARED, settingsfd, 0);
	if (daemon_settings == MAP_FAILED) {
		cleanup_daemon_files(false); // Keep settings for the next launch
		close(settingsfd);
		exit(0);
	}
	close(settingsfd);
	if (!daemon_settings_valid(daemon_settings)) {
		NSLog(CFSTR("Daemon: Invalid charging-limit settings, exiting"));
		munmap(daemon_settings, BATTMAN_DAEMON_SETTINGS_SIZE);
		daemon_settings = NULL;
		cleanup_daemon_files(false); // Keep settings for the next launch
		exit(0);
	}
	if (smc_open() != kIOReturnSuccess) {
		/* Charging-limit control depends on AppleSMC. Keep the app usable on
		 * simulators/unsupported hardware, but never leave an apparently active
		 * daemon with a PID/socket that cannot perform the requested operation. */
		NSLog(CFSTR("Daemon: AppleSMC is unavailable; charging-limit daemon disabled"));
		munmap(daemon_settings, BATTMAN_DAEMON_SETTINGS_SIZE);
		daemon_settings = NULL;
		cleanup_daemon_files(false);
		exit(0);
	}
	// FIXME: Implement standalone listeners for daemon
	subscribeToPowerEvents(powerevent_listener);
	/* Matching notifications register interest callbacks but do not replay the
	 * current capacity.  Apply the persisted policy once at startup so a newly
	 * launched daemon does not wait for the next battery event (or silently
	 * leave charging in the previous state). */
	io_service_t initial_power_source = IOServiceGetMatchingService(
		0, IOServiceMatching("IOPMPowerSource"));
	if (initial_power_source != IO_OBJECT_NULL) {
		powerevent_listener(0, initial_power_source, -536723200);
		IOObjectRelease(initial_power_source);
	}
	pthread_t tmp;
	if (pthread_create(&tmp, NULL, daemon_control, NULL) == 0) {
		pthread_join(tmp, NULL);
	} else {
		NSLog(CFSTR("Daemon: Failed to start control thread"));
	}
	if (daemon_settings && daemon_settings != MAP_FAILED)
		munmap(daemon_settings, BATTMAN_DAEMON_SETTINGS_SIZE);
	daemon_settings = NULL;
	cleanup_daemon_files(false);
}

int battman_run_daemon(void) {
	posix_spawnattr_t sattr = NULL;
	pid_t dpid = 0;
	int err;
	const char *failed_step = NULL;

	err = posix_spawnattr_init(&sattr);
	if (err != 0) {
		failed_step = "posix_spawnattr_init";
		goto out;
	}

#define BATTMAN_SET_SPAWN_ATTR(step, expr) \
	do { \
		err = (expr); \
		if (err != 0) { \
			failed_step = (step); \
			goto out; \
		} \
	} while (0)

	BATTMAN_SET_SPAWN_ATTR("posix_spawnattr_set_persona_np",
	    posix_spawnattr_set_persona_np(&sattr, BATTMAN_ROOT_PERSONA_ID, POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE));
	BATTMAN_SET_SPAWN_ATTR("posix_spawnattr_set_persona_uid_np",
	    posix_spawnattr_set_persona_uid_np(&sattr, 0));
	BATTMAN_SET_SPAWN_ATTR("posix_spawnattr_set_persona_gid_np",
	    posix_spawnattr_set_persona_gid_np(&sattr, 0));
	BATTMAN_SET_SPAWN_ATTR("posix_spawnattr_setprocesstype_np",
	    posix_spawnattr_setprocesstype_np(&sattr, POSIX_SPAWN_PROC_TYPE_DAEMON_STANDARD));
	// XXX: Consider force to UI role, since this was not a real launchdaemon
	// posix_spawnattr_set_darwin_role_np(&attr, PRIO_DARWIN_ROLE_UI);

	BATTMAN_SET_SPAWN_ATTR("posix_spawnattr_setjetsam_ext",
	    posix_spawnattr_setjetsam_ext(&sattr, 0, battman_daemon_jetsam_priority(),
	    BATTMAN_DAEMON_MEMLIMIT_MIB, BATTMAN_DAEMON_MEMLIMIT_MIB));
	BATTMAN_SET_SPAWN_ATTR("posix_spawnattr_setflags",
	    posix_spawnattr_setflags(&sattr, POSIX_SPAWN_SETSID));

#undef BATTMAN_SET_SPAWN_ATTR

	char executable[1024];
	uint32_t size = 1024;
	if (_NSGetExecutablePath(executable, &size) != 0) {
		err = ENAMETOOLONG;
		failed_step = "_NSGetExecutablePath";
		goto out;
	}
	char *newargv[] = {executable, "--daemon", NULL};
	err = posix_spawn(&dpid, executable, NULL, &sattr, (char **)newargv, environ);
	if (err != 0) {
		failed_step = "posix_spawn";
	}

out:
	if (err != 0) {
		NSLog(CFSTR("Daemon: %s failed: %s"), failed_step ? failed_step : "spawn setup", strerror(err));
		show_alert(L_ERR, strerror(err), L_OK);
		dpid = 0;
	}
	if (sattr != NULL)
		posix_spawnattr_destroy(&sattr);
	return dpid;
}
