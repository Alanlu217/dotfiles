local autostart = {
  "waybar",
  "udiskie",
  "~/dotfiles/scripts/wpaper start",
  "~/dotfiles/scripts/low_bat.py",
}

hl.on("hyprland.start", function()
  for _, cmd in ipairs(autostart) do
    hl.exec_cmd(cmd)
  end
end)
