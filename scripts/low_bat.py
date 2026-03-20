#!/usr/bin/env python3

from datetime import timedelta
from time import sleep
from os import system

theshold = 20
interval = timedelta(minutes=2)

while True:
    with open("/sys/class/power_supply/BAT0/capacity") as f:
        p = int(f.readline())

    with open("/sys/class/power_supply/BAT0/status") as f:
        status = f.readline().strip()

    if p < theshold and "Discharging" in status:
        system(f'notify-send -u critical "Low Battery: {p}%"')

    sleep(interval.total_seconds())
