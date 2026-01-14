#!/usr/bin/env nu

const threshold = 20
const interval = 60sec

def get-battery-percentage [] {
    ^upower -b | parse -r "percentage: +([0-9]+)%" | get 0 | get capture0 | into int
}

loop {
    let p = (get-battery-percentage)

    if $p < $threshold {
        ^notify-send -u critical $"Low Battery: ($p)%"
    }

    sleep $interval
}

