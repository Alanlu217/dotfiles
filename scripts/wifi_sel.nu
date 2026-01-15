#!/usr/bin/env nu

let connections = (^nmcli c show |
    lines |
    skip 1 |
    split column ' ' --collapse-empty |
    where column2 == 'wifi' |
    get column0)

let target = ($connections | str join (char nl) | ^rofi -dmenu | str trim)

if $target != '' {
    ^nmcli c up $target
}
