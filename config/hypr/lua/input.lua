hl.config({
  input = {
    kb_layout     = "us",
    kb_options    = "caps:escape",

    follow_mouse  = 1,
    accel_profile = "flat",
    sensitivity   = 0, -- -1.0 - 1.0, 0 means no modification

    repeat_delay  = 240,
    repeat_rate   = 24,

    touchpad      = {
      natural_scroll       = true,
      disable_while_typing = false,
      scroll_factor        = 0.5,
      clickfinger_behavior = 1,
      tap_to_click         = false,
    },
  },
})

hl.device({
  name        = "syna2ba6:00-06cb:cf00-touchpad",
  sensitivity = 0.8,
})

hl.device({
  name           = "razer-razer-viper-8khz-keyboard-1",
  scroll_factor  = 1.5,
  natural_scroll = true,
})

---------------------
----  GESTURES   ----
---------------------

hl.gesture({ fingers = 3, direction = "vertical", action = "workspace" })
hl.gesture({ fingers = 3, direction = "horizontal", action = "scroll_move" }) -- scroll through columns
hl.gesture({ fingers = 3, direction = "swipe", mods = "SUPER", action = "resize" })
hl.gesture({ fingers = 3, direction = "pinch", action = "cursorZoom", mode = "live" })
hl.gesture({ fingers = 4, direction = "vertical", action = "fullscreen" })
hl.gesture({ fingers = 4, direction = "pinch", action = "close" })
