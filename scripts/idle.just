running:
    #!/usr/bin/env bash

    if [ "$(pidof swayidle)" == "" ]; then
        echo off
    else
        echo on
    fi

start:
    ~/dotfiles/scripts/idle.py &
    pkill -RTMIN+1 waybar

stop:
    pkill swayidle
    pkill -RTMIN+1 waybar

toggle:
    #!/usr/bin/env bash

    if [ "$(pidof swayidle)" == "" ]; then
        ~/dotfiles/scripts/idle.py &
        pkill -RTMIN+1 waybar
        pkill -RTMIN+1 .waybar-wrapped
    else
        killall swayidle
        pkill -RTMIN+1 waybar
        pkill -RTMIN+1 .waybar-wrapped
    fi
    
