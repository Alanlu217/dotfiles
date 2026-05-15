local autostart = {
    "waybar",
    "udiskie",
    "xwayland-satellite",
    "~/dotfiles/scripts/wpaper start",
    "~/dotfiles/scripts/idle start",
    "~/dotfiles/scripts/low_bat.py",
    "hyprctl setcursor Adwaita 24",
}

hl.on("hyprland.start", function ()
    for _, v in ipairs(autostart) do
         hl.exec_cmd(v)
    end
end)
