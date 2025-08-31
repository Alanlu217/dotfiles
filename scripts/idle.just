running:
    #!/usr/bin/env bash

    if [ "$(pidof swayidle)" == "" ]; then
        echo off
    else
        echo on
    fi

start:
    bash ~/dotfiles/scripts/niriidle.sh &
    pkill -RTMIN+1 waybar

stop:
    pkill swayidle
    pkill -RTMIN+1 waybar

toggle:
    #!/usr/bin/env bash

    if [ "$(pidof swayidle)" == "" ]; then
        bash ~/dotfiles/scripts/niriidle.sh &
        pkill -RTMIN+1 waybar
        pkill -RTMIN+1 .waybar-wrapped
    else
        killall swayidle
        pkill -RTMIN+1 waybar
        pkill -RTMIN+1 .waybar-wrapped
    fi
    
