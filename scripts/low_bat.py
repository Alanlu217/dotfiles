#!/usr/bin/env python3
"""Send a critical notification when the battery is low and discharging."""

import subprocess
from pathlib import Path
from time import sleep

BATTERY = Path("/sys/class/power_supply/BAT0")
THRESHOLD = 20  # percent
INTERVAL = 120  # seconds


def check() -> None:
    try:
        percent = int((BATTERY / "capacity").read_text())
        discharging = (BATTERY / "status").read_text().strip() == "Discharging"
        if discharging and percent < THRESHOLD:
            subprocess.run(
                ["notify-send", "-u", "critical", f"Low Battery: {percent}%"]
            )
    except (OSError, ValueError):
        pass  # transient sysfs read error or notify-send missing; retry next interval


if __name__ == "__main__":
    while True:
        check()
        sleep(INTERVAL)
