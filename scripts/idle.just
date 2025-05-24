running:
    #!/usr/bin/env bash

    if [ "$(pidof hypridle)" == "" ]; then
        echo off
    else
        echo on
    fi

start:
    hyprctl dispatch exec hypridle
    pkill -RTMIN+1 waybar

stop:
    killall hypridle
    pkill -RTMIN+1 waybar

toggle:
    #!/usr/bin/env bash

    if [ "$(pidof hypridle)" == "" ]; then
        hyprctl dispatch exec hypridle
        pkill -RTMIN+1 waybar
    else
        killall hypridle
        pkill -RTMIN+1 waybar
    fi
    
