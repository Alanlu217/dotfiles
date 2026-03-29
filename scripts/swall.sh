#!/usr/bin/env fish

set wall_dir ~/dotfiles/wallpapers
set name (ls $wall_dir | rofi -dmenu)

if test -z "$name"
    exit
end

set wall "$wall_dir/$name"

if command -q swww
    set setter swww
else if command -q awww
    set setter awww
else
    echo "Error: neither swww nor awww found" >&2
    exit 1
end

$setter img --transition-step=4 --transition-fps 120 "$wall" &
$setter img -n overlay --transition-step=4 --transition-fps 120 "$wall" &

rm -f ~/.curr_bg
ln -s "$wall" ~/.curr_bg
