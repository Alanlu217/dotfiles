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
    killall swayidle
    pkill -RTMIN+1 waybar

toggle:
    #!/usr/bin/env bash

    if [ "$(pidof swayidle)" == "" ]; then
        bash ~/dotfiles/scripts/niriidle.sh &
        pkill -RTMIN+1 waybar
    else
        killall swayidle
        pkill -RTMIN+1 waybar
    fi
    
