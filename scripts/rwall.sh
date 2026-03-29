#!/usr/bin/env fish

set wall_dir ~/dotfiles/wallpapers
set wall (ls $wall_dir | shuf -n 1)

if command -q swww
    set setter swww
else if command -q awww
    set setter awww
else
    echo "Error: neither swww nor awww found" >&2
    exit 1
end

$setter img --transition-step=4 --transition-fps 120 "$wall_dir/$wall" &
$setter img -n overlay --transition-step=4 --transition-fps 120 "$wall_dir/$wall" &

rm -f ~/.curr_bg
ln -s "$wall_dir/$wall" ~/.curr_bg
