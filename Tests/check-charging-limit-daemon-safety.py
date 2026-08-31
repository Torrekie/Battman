#!/usr/bin/env python3
"""Static regression checks for the charging-limit daemon boundary.

These checks deliberately avoid starting a privileged daemon or touching a
device.  They keep the small client/daemon protocol from regressing into
unbounded reads, SIGPIPE-prone writes, or a pointer-sized mmap sync.
"""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CLIENT = (ROOT / "Battman/ChargingLimitViewController.m").read_text(encoding="utf-8")
CM = (ROOT / "Battman/ChargingManagementViewController.m").read_text(encoding="utf-8")
SLIDER = (ROOT / "Battman/SliderTableViewCell.m").read_text(encoding="utf-8")
HEADER = (ROOT / "Battman/common.h").read_text(encoding="utf-8")
DAEMON = (ROOT / "Battman/battery_utils/daemon.c").read_text(encoding="utf-8")


def require(text: str, needle: str, label: str) -> None:
    if needle not in text:
        raise SystemExit(f"FAIL: missing {label}: {needle}")


require(HEADER, "#define BATTMAN_DAEMON_SETTINGS_SIZE 3u", "shared settings size")
require(CLIENT, "daemon_fd = -1", "invalid descriptor sentinel")
require(CLIENT, "SO_RCVTIMEO", "bounded daemon receive timeout")
require(CLIENT, "SO_SNDTIMEO", "bounded daemon send timeout")
require(CLIENT, "SO_NOSIGPIPE", "SIGPIPE protection")
require(CLIENT, "MSG_NOSIGNAL", "SIGPIPE-safe send")
require(CLIENT, "MAP_FAILED", "portable mmap failure check")
require(CLIENT, "msync(vals, BATTMAN_DAEMON_SETTINGS_SIZE", "exact settings sync length")
require(CLIENT, "sendDaemonCommand:(char)command reconnect:", "reconnect-aware command path")
require(CLIENT, "fstat(fd, &locked_stat)", "client stale-run inode snapshot")
require(CLIENT, "lstat(run_path, &path_stat)", "client stale-run pathname revalidation")
require(CLIENT, "locked_stat.st_ino != path_stat.st_ino", "client stale-run inode mismatch guard")
require(CM, "else if ([object respondsToSelector:@selector(getPowerMode)])", "legacy optional LPM getter")
require(CM, "static BOOL CLReadNotifyState", "legacy LPM notify read helper")
require(CM, "static BOOL CLWriteNotifyState", "legacy LPM notify write helper")
require(CM, "Older systems exposed the notify state", "legacy notify-only fallback documentation")
require(CM, "BOOL bundleLoaded = bundle && [bundle loadAndReturnError:nil];", "LPM bundle load gate")
require(CM, "CLWriteNotifyState(system_lpm_notif, requested, &notifyActual)", "legacy notify write/readback fallback")
require(CM, "if (@available(iOS 16.0, macOS 13.0, *))\n\t\t\treturn NO;", "legacy-only notify fallback gate")
require(CLIENT, "values[0] != 255 && values[1] == 255", "reject resume-only threshold state")
require(CLIENT, "return values[0] == 255 || values[0] < values[1]", "require resume below limit")
require(CLIENT, "if ((unsigned char)vals[1] == 255)\n\t\t\tvals[1] = 100", "seed a paired limit when resume mode is enabled")
require(SLIDER, "sliderTableViewCell:self didEndChangingValue:newValue", "commit typed threshold edits")
require(CLIENT, "int resumeThreshold = (unsigned char)vals[0];", "unsigned UI resume threshold")
require(CLIENT, "resumeThreshold != 255 && (int)rounded <= resumeThreshold", "prevent equal UI thresholds")
require(DAEMON, "cleanup_daemon_files(false)", "preserve settings on daemon stop")
require(DAEMON, "daemon_unlink_locked_run_path(cleanup_path, held_run_fd, &removed_run_path)", "inode-checked daemon cleanup")
require(DAEMON, "daemon_mark_run_stopping", "shutdown PID marker")
require(DAEMON, "pid_t stopping_pid = 0", "non-live shutdown marker value")
require(DAEMON, "BATTMAN_MAX_CONTROL_CLIENTS 8", "bounded daemon client count")
require(DAEMON, "daemon_try_acquire_control_client", "bounded daemon client admission")
require(DAEMON, "usleep(10000)", "accept error backoff")
require(DAEMON, "const char *socket_path = battman_socket_path()", "centralized socket path cleanup")
require(DAEMON, "daemon_set_socket_path_permissions", "path-based socket permission helper")
require(DAEMON, "daemon_remove_stale_socket_path", "typed stale socket cleanup")
require(DAEMON, "if (!S_ISSOCK(st.st_mode))", "refuse non-socket stale path removal")
require(DAEMON, "lstat(path, &before) != 0 || !S_ISSOCK(before.st_mode)", "socket-path type validation")
require(DAEMON, "lchown(path, (uid_t)-1, mobile_gid)", "socket group-only ownership change")
require(DAEMON, "before.st_ino != after_mode.st_ino", "socket-path inode revalidation")
require(DAEMON, "fchmodat(AT_FDCWD, path", "path-based socket mode")
require(DAEMON, "Control socket path changed during setup", "pre-listen socket-path revalidation")
require(DAEMON, "listening_path.st_ino != owned_socket_stat.st_ino", "pre-listen socket inode identity")
require(DAEMON, "daemon_settings == MAP_FAILED", "daemon mmap failure check")
require(DAEMON, "smc_open() != kIOReturnSuccess", "unsupported AppleSMC degradation")
require(DAEMON, "mkstemp(temporary_run_path)", "private PID publication inode")
require(DAEMON, "link(temporary_run_path, run_path)", "non-replacing PID publication")
require(DAEMON, "daemon_unlink_locked_run_path", "inode-checked PID cleanup helper")
require(DAEMON, "fstat(locked_fd, &locked_stat)", "locked PID inode snapshot")
require(DAEMON, "lstat(path, &path_stat)", "run-path inode revalidation")
require(DAEMON, "locked_stat.st_ino != path_stat.st_ino", "run-path inode mismatch guard")
require(DAEMON, "settings->enable_charging_at_level >= settings->disable_charging_at_level", "reject equal charging thresholds")
require(DAEMON, "int inhibit_charging = -1", "tri-state hysteresis policy")
require(DAEMON, "Between the two thresholds, retain the hardware's prior state", "safe hysteresis midpoint")
require(DAEMON, "settings->enable_charging_at_level != 255 &&\n\t    settings->disable_charging_at_level == 255", "reject daemon resume-only threshold state")

for forbidden, label in (
    ("write(daemon_fd", "raw client write"),
    ("read(daemon_fd", "raw client read"),
    ("msync(vals, sizeof(vals)", "pointer-sized mmap sync"),
):
    if forbidden in CLIENT:
        raise SystemExit(f"FAIL: {label} remains: {forbidden}")

if "unlink(socket_path)" in DAEMON:
    raise SystemExit("FAIL: cleanup may unlink a replacement daemon socket")
if "fchmod(sock," in DAEMON or "fchown(sock," in DAEMON:
    raise SystemExit("FAIL: socket permissions applied to descriptor instead of bound path")
if "power_switch_safe(val," in DAEMON:
    raise SystemExit("FAIL: raw battery percentage passed as inhibit bit")

print("charging-limit daemon safety checks: PASS")
