-- Keybindings. Workspace keys (Mod+0-9, workspace up/down, wheel) live in
-- lua/monitor_workspaces.lua. Mirrors the niri binds where there is an equivalent.

local mainMod     = "SUPER"
local terminal    = "alacritty"
local fileManager = "thunar"
local browser     = "firefox"
local menu        = "rofi -show drun"

local function mod(keys)
  return mainMod .. " + " .. keys
end

---------------------
----   PROGRAMS  ----
---------------------

hl.bind(mod("X"), hl.dsp.exec_cmd(terminal))
hl.bind(mod("B"), hl.dsp.exec_cmd(browser))
hl.bind(mod("E"), hl.dsp.exec_cmd(fileManager))
hl.bind(mod("Space"), hl.dsp.exec_cmd(menu))
hl.bind("ALT + Space", hl.dsp.exec_cmd("rofi -show window"))

hl.bind(mod("G"), hl.dsp.exec_cmd('grim -g "$(slurp -d)" - | wl-copy'))

hl.bind(mod("Grave"), hl.dsp.exec_cmd("~/dotfiles/scripts/wpaper random"))
hl.bind(mod("SHIFT + Grave"), hl.dsp.exec_cmd("~/dotfiles/scripts/wpaper pick"))

---------------------
----   SESSION   ----
---------------------

hl.bind(mod("M"), hl.dsp.exec_cmd("hyprlock"))
hl.bind(mod("SHIFT + E"), hl.dsp.exit())
hl.bind(mod("SHIFT + P"), hl.dsp.exec_cmd("~/dotfiles/scripts/idle now"))

---------------------
----   WINDOWS   ----
---------------------

hl.bind(mod("SHIFT + Q"), hl.dsp.window.close())
hl.bind(mod("V"), hl.dsp.window.float({ action = "toggle" }))
hl.bind(mod("F"), hl.dsp.window.fullscreen())
hl.bind(mod("ALT + F"), hl.dsp.window.fullscreen_state({ internal = 0, client = 2, action = "toggle" }))

-- Mouse: drag to move, right-drag to resize
hl.bind(mod("mouse:272"), hl.dsp.window.drag(), { mouse = true })
hl.bind(mod("mouse:273"), hl.dsp.window.resize(), { mouse = true })

---------------------
----   FOCUS     ----
---------------------
-- Left/right use the scrolling layout (columns; stops at the ends because of
-- wrap_focus/wrap_swapcol in look.lua). Up/down move within a column.

local directions = {
  left  = { keys = { "left", "A", "H" }, focus = "focus l", swap = "swapcol l", resize = { x = -10, y = 0 } },
  right = { keys = { "right", "D", "L" }, focus = "focus r", swap = "swapcol r", resize = { x = 10, y = 0 } },
  up    = { keys = { "up", "W", "K" }, resize = { x = 0, y = -10 } },
  down  = { keys = { "down", "S", "J" }, resize = { x = 0, y = 10 } },
}

for dir, d in pairs(directions) do
  for _, key in ipairs(d.keys) do
    -- Focus
    hl.bind(mod(key),
      d.focus and hl.dsp.layout(d.focus) or hl.dsp.focus({ direction = dir }))
    -- Move (swap whole columns left/right, move a window up/down)
    hl.bind(mod("SHIFT + " .. key),
      d.swap and hl.dsp.layout(d.swap) or hl.dsp.window.move({ direction = dir }))
    -- Resize
    hl.bind(mod("SHIFT + CTRL + " .. key),
      hl.dsp.window.resize({ relative = true, x = d.resize.x, y = d.resize.y }),
      { repeating = true })
  end
end

---------------------
----   COLUMNS   ----
---------------------

-- Consume into the neighbouring column if alone, otherwise expel into a new column
hl.bind(mod("bracketleft"), hl.dsp.layout("consume_or_expel prev"))
hl.bind(mod("bracketright"), hl.dsp.layout("consume_or_expel next"))

-- Column width: +/-5% of the screen, or reset to 50%
hl.bind(mod("minus"), hl.dsp.layout("colresize -0.05"), { repeating = true })
hl.bind(mod("equal"), hl.dsp.layout("colresize +0.05"), { repeating = true })
hl.bind(mod("R"), hl.dsp.layout("colresize 0.5"))

-- Window height within a column
hl.bind(mod("SHIFT + minus"), hl.dsp.window.resize({ x = 0, y = -50, relative = true }), { repeating = true })
hl.bind(mod("SHIFT + equal"), hl.dsp.window.resize({ x = 0, y = 50, relative = true }), { repeating = true })

---------------------
----   MONITORS  ----
---------------------
-- Workspaces are pinned per monitor, so windows (not workspaces) move across.

hl.bind(mod("Z"), hl.dsp.focus({ monitor = "l" }))
hl.bind(mod("C"), hl.dsp.focus({ monitor = "r" }))
hl.bind(mod("SHIFT + Z"), hl.dsp.window.move({ monitor = "l", follow = true }))
hl.bind(mod("SHIFT + C"), hl.dsp.window.move({ monitor = "r", follow = true }))

---------------------
----     MEDIA   ----
---------------------

local locked = { locked = true }
local locked_repeat = { locked = true, repeating = true }

hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), locked_repeat)
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"), locked_repeat)
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), locked_repeat)
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), locked_repeat)
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%+"), locked_repeat)
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%-"), locked_repeat)

-- Requires playerctl
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), locked)
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), locked)
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), locked)
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), locked)
hl.bind(mod("CTRL + right"), hl.dsp.exec_cmd("playerctl next"), locked)
hl.bind(mod("CTRL + Space"), hl.dsp.exec_cmd("playerctl play-pause"), locked)
hl.bind(mod("CTRL + left"), hl.dsp.exec_cmd("playerctl previous"), locked)
