local env = {
    HYPRCURSOR_THEME = "Adwaita",
    HYPRCURSOR_SIZE = "24",
    XCURSOR_THEME = "Adwaita",
    XCURSOR_SIZE = "24",
    XDG_CURRENT_DESKTOP = "Hyprland",
    XDG_SESSION_TYPE = "wayland",
    XDG_SESSION_DESKTOP = "Hyprland",
    QT_QPA_PLATFORMTHEME = "qt6ct",
    GTK_THEME_VARIANT = "dark",
    ELECTRON_ENABLE_WAYLAND = "1",
    ELECTRON_OZONE_PLATFORM_HINT = "wayland",
}

for k, v in pairs(env) do
    hl.env(k, v)
end
