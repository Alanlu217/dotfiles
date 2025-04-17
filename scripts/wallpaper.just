alias r:=random
alias s:=select

random:
    #!/usr/bin/env bash
    wall="$(pwd)/../wallpapers/$(ls ../wallpapers | shuf -n 1)"
    hyprctl hyprpaper reload ",$wall"
    rm -rf ~/.curr_bg
    ln -s "$wall" ~/.curr_bg

select:
    #!/usr/bin/env bash
    name="$(ls ../wallpapers | rofi -dmenu)"
    if [ "${name}" == "" ]; then exit; fi
    wall="$(pwd)/../wallpapers/$name"
    hyprctl hyprpaper reload ",$wall"
    rm -rf ~/.curr_bg
    ln -s "$wall" ~/.curr_bg

setup:
    rm -rf ~/.curr_bg
    ln -s ~/dotfiles/wallpapers/dark-flowers.png ~/.curr_bg
