local terminal    = "alacritty"
local fileManager = "thunar"
local browser     = "firefox"
local menu        = "rofi -show drun"

hl.config({
    input = {
        kb_layout  = "us",
        kb_variant = "",
        kb_model   = "",
        kb_options = "caps:escape",
        kb_rules   = "",

        follow_mouse = 1,
        accel_profile = "flat",

        repeat_delay = 240,
        repeat_rate = 24,

        sensitivity = 0, -- -1.0 - 1.0, 0 means no modification.

        touchpad = {
            natural_scroll = true,
            disable_while_typing = false,
            scroll_factor = 0.5,
            clickfinger_behavior = 1,
            tap_to_click = false
        },
    },
})

hl.gesture({
    fingers = 3,
    direction = "vertical",
    action = "workspace",
})

hl.gesture({
    fingers = 3,
    direction = "swipe",
    mods = "SUPER",
    action = "resize",
})

hl.gesture({
    fingers = 4,
    direction = "vertical",
    action = "fullscreen",
})

hl.gesture({
    fingers = 4,
    direction = "pinch",
    action = "close",
})

hl.gesture({ fingers = 3, direction = "pinch", action = "cursorZoom", mode = "live" })

hl.device({
    name = "syna2ba6:00-06cb:cf00-touchpad",
    sensitivity = 0.8,
})

hl.device({
    name = "razer-razer-viper-8khz-keyboard-1",
    scroll_factor = 1.5,
    natural_scroll = true,
})


---------------------
---- KEYBINDINGS ----
---------------------

local mainMod = "SUPER" -- Sets "Windows" key as main modifier

-- Example binds, see https://wiki.hypr.land/Configuring/Basics/Binds/ for more
hl.bind(mainMod .. " + Space", hl.dsp.exec_cmd(menu))
hl.bind("ALT + Space", hl.dsp.exec_cmd("rofi -show window"))

hl.bind(mainMod .. " + X", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + B", hl.dsp.exec_cmd(browser))
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(fileManager))

hl.bind(mainMod .. " + F", hl.dsp.window.fullscreen())

hl.bind(mainMod .. " + G", hl.dsp.exec_cmd("grim -g \"$(slurp -d)\" - | wl-copy"))

hl.bind(mainMod .. " + Grave", hl.dsp.exec_cmd("~/dotfiles/scripts/wpaper random"))
hl.bind(mainMod .. " + SHIFT + Grave",
    hl.dsp.exec_cmd("~/dotfiles/scripts/wpaper pick"))

hl.bind(mainMod .. " + L", hl.dsp.exec_cmd("hyprlock"))
hl.bind(mainMod .. " + SHIFT + L", hl.dsp.exit())
hl.bind(mainMod .. " + SHIFT + P", hl.dsp.exec_cmd("~/dotfiles/scripts/idle now"))

hl.bind(mainMod .. " + SHIFT + Q", hl.dsp.window.close())
hl.bind(mainMod .. " + V", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + P", hl.dsp.window.pseudo())
hl.bind(mainMod .. " + J", hl.dsp.layout("togglesplit"))    -- dwindle only

-- Move focus with mainMod + arrow keys
local directions = {
    left = {"left", "A", "H"},
    right = {"right", "D", "L"},
    up = {"up", "W", "K"},
    down = {"down", "S", "J"},
}
local dir_to_resize = {
    left = {x = -10, y = 0},
    right = {x = 10, y = 0},
    up = {x = 0, y = 10},
    down = {x = 0, y = -10},
}
for dir, binds in pairs(directions) do
    for _, v in ipairs(binds) do
        -- Focus
        hl.bind(mainMod .. " + " .. v,
            hl.dsp.focus({ direction = dir }))
        -- Move
        hl.bind(mainMod .. " + SHIFT + " .. v,
            hl.dsp.window.move({ direction = dir }))
        -- Resize
        hl.bind(mainMod .. " + SHIFT + CTRL + " .. v,
            hl.dsp.window.resize({relative = true, x = dir_to_resize[dir].x, y = dir_to_resize[dir].y}), {repeating = true})
    end
end

-- Move monitors
hl.bind(mainMod .. " + Z", hl.dsp.focus({monitor = "l"}))
hl.bind(mainMod .. " + C", hl.dsp.focus({monitor = "r"}))
hl.bind(mainMod .. " + SHIFT + Z", hl.dsp.workspace.move({monitor = "l"}))
hl.bind(mainMod .. " + SHIFT + C", hl.dsp.workspace.move({monitor = "r"}))

-- Switch workspaces with mainMod + [0-9]
-- Move active window to a workspace with mainMod + SHIFT + [0-9]
for i = 1, 10 do
    local key = i % 10 -- 10 maps to key 0
    hl.bind(mainMod .. " + " .. key,             hl.dsp.focus({ workspace = i}))
    hl.bind(mainMod .. " + SHIFT + " .. key,     hl.dsp.window.move({ workspace = i, follow = false }))
end

-- Example special workspace (scratchpad)
hl.bind(mainMod .. " + S",         hl.dsp.workspace.toggle_special("magic"))
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic" }))

-- Scroll through existing workspaces with mainMod + scroll
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))

-- Move/resize windows with mainMod + LMB/RMB and dragging
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Laptop multimedia keys for volume and LCD brightness
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),      { locked = true, repeating = true })
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),     { locked = true, repeating = true })
hl.bind("XF86AudioMicMute",     hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),   { locked = true, repeating = true })
hl.bind("XF86MonBrightnessUp",  hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%+"),                  { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown",hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%-"),                  { locked = true, repeating = true })

-- Requires playerctl
hl.bind("XF86AudioNext",  hl.dsp.exec_cmd("playerctl next"),       { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd("playerctl previous"),   { locked = true })
hl.bind(mainMod .. " + CTRL + right",  hl.dsp.exec_cmd("playerctl next"),       { locked = true })
hl.bind(mainMod .. " + CTRL + down",  hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind(mainMod .. " + CTRL + up",  hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind(mainMod .. " + CTRL + left",  hl.dsp.exec_cmd("playerctl previous"),   { locked = true })

