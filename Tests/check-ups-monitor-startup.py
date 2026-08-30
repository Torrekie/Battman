#!/usr/bin/env python3

from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
SOURCE = (REPO_ROOT / "Battman" / "UPSMonitor-new.m").read_text(encoding="utf-8")


def braced_block_after(marker: str) -> str:
    marker_offset = SOURCE.find(marker)
    if marker_offset < 0:
        raise AssertionError(f"missing source marker: {marker}")
    start = SOURCE.find("{", marker_offset)
    if start < 0:
        raise AssertionError(f"missing block after source marker: {marker}")

    depth = 0
    for offset in range(start, len(SOURCE)):
        character = SOURCE[offset]
        if character == "{":
            depth += 1
        elif character == "}":
            depth -= 1
            if depth == 0:
                return SOURCE[start : offset + 1]
    raise AssertionError(f"unterminated block after source marker: {marker}")


thread_main = braced_block_after("threadMain(void *context)")
ready_offset = thread_main.find("gWatchThreadReady = true;")
initial_drain_offset = thread_main.find("UPSDeviceAdded(NULL, gAddedIter);")
assert ready_offset >= 0, "UPS watch thread no longer publishes readiness"
assert initial_drain_offset >= 0, "UPS watch thread no longer performs its initial drain"
assert ready_offset < initial_drain_offset, (
    "initial UPS device materialization must not block application launch readiness"
)

termination = braced_block_after("+ (void)appWillTerminate:")
assert "cleanupAllResources" not in termination, (
    "application termination must not synchronously join the IOKit watch thread"
)
assert "pthread_join" not in termination, (
    "application termination must not wait for the IOKit watch thread"
)

print("UPS monitor startup and termination contracts passed.")
