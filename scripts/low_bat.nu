#!/usr/bin/env nu

const threshold = 20
const interval = 2min

loop {
    let upower = ^upower -b
    let p = $upower | parse -r "percentage: +([0-9]+)%" | get 0 | get capture0 | into int
    let discharging = $upower | str contains "discharging"

    if $p < $threshold and $discharging {
        ^notify-send -u critical $"Low Battery: ($p)%"
    }

    sleep $interval
}

