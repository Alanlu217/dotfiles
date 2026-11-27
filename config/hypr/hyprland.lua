-- Hyprland config. Each module lives in lua/.

require("lua.env")                -- environment variables
require("lua.autostart")          -- programs started with the session
require("lua.monitors")           -- outputs, modes, positions, scales
require("lua.monitor_workspaces") -- per-monitor workspaces + their keys
require("lua.look")               -- gaps, borders, animations, layout
require("lua.input")              -- keyboard, touchpad, gestures
require("lua.binds")              -- keybindings
require("lua.windows")            -- window rules
