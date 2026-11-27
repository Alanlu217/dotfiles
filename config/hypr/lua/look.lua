hl.config({
  general = {
    layout           = "scrolling",
    gaps_in          = 1,
    gaps_out         = 2,
    border_size      = 1,
    resize_on_border = true, -- drag borders/gaps to resize
    allow_tearing    = false,

    col              = {
      active_border   = "rgba(8888ffee)",
      inactive_border = "rgba(595959aa)",
    },
  },

  decoration = {
    rounding         = 0,
    rounding_power   = 2,
    active_opacity   = 1.0,
    inactive_opacity = 1.0,

    shadow           = {
      enabled      = false,
      range        = 4,
      render_power = 3,
      color        = 0xee1a1a1a,
    },

    blur             = {
      enabled  = false,
      size     = 3,
      passes   = 1,
      vibrancy = 0.1696,
    },
  },

  scrolling = {
    fullscreen_on_one_column = true,
    wrap_focus               = false, -- stop at the first/last column
    wrap_swapcol             = false,
  },

  xwayland = {
    enabled            = true,
    force_zero_scaling = true,
  },

  animations = {
    enabled = true,
  },

  misc = {
    disable_hyprland_logo      = true,
    initial_workspace_tracking = false,
  },

  ecosystem = {
    no_update_news  = true,
    no_donation_nag = true,
  },
})

---------------------
---- ANIMATIONS  ----
---------------------
-- Defaults, see https://wiki.hypr.land/Configuring/Advanced-and-Cool/Animations/

hl.curve("easeOutQuint", { type = "bezier", points = { { 0.23, 1 }, { 0.32, 1 } } })
hl.curve("easeInOutCubic", { type = "bezier", points = { { 0.65, 0.05 }, { 0.36, 1 } } })
hl.curve("linear", { type = "bezier", points = { { 0, 0 }, { 1, 1 } } })
hl.curve("almostLinear", { type = "bezier", points = { { 0.5, 0.5 }, { 0.75, 1 } } })
hl.curve("quick", { type = "bezier", points = { { 0.15, 0 }, { 0.1, 1 } } })
hl.curve("easy", { type = "spring", mass = 1, stiffness = 1024, dampening = 64 })

hl.animation({ leaf = "global", enabled = true, speed = 10, bezier = "default" })
hl.animation({ leaf = "border", enabled = true, speed = 5.39, bezier = "easeOutQuint" })
hl.animation({ leaf = "windows", enabled = true, speed = 4.79, spring = "easy" })
hl.animation({ leaf = "windowsIn", enabled = true, speed = 4.1, spring = "easy", style = "popin 87%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 1.49, bezier = "linear", style = "popin 87%" })
hl.animation({ leaf = "fadeIn", enabled = true, speed = 1.73, bezier = "almostLinear" })
hl.animation({ leaf = "fadeOut", enabled = true, speed = 1.46, bezier = "almostLinear" })
hl.animation({ leaf = "fade", enabled = true, speed = 3.03, bezier = "quick" })
hl.animation({ leaf = "layers", enabled = true, speed = 3.81, bezier = "easeOutQuint" })
hl.animation({ leaf = "layersIn", enabled = true, speed = 4, bezier = "easeOutQuint", style = "fade" })
hl.animation({ leaf = "layersOut", enabled = true, speed = 1.5, bezier = "linear", style = "fade" })
hl.animation({ leaf = "fadeLayersIn", enabled = true, speed = 1.79, bezier = "almostLinear" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 1.39, bezier = "almostLinear" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 2, bezier = "quick", style = "slidevert" })
hl.animation({ leaf = "workspacesIn", enabled = true, speed = 2, bezier = "quick", style = "slidevert" })
hl.animation({ leaf = "workspacesOut", enabled = true, speed = 2, bezier = "quick", style = "slidevert" })
hl.animation({ leaf = "zoomFactor", enabled = true, speed = 7, bezier = "quick" })

---------------------
---- SMART GAPS  ----
---------------------
-- No gaps or borders when a workspace has a single (tiled or fullscreen) window.
-- Ref https://wiki.hypr.land/Configuring/Basics/Workspace-Rules/

hl.workspace_rule({ workspace = "w[tv1]", gaps_out = 0, gaps_in = 0 })
hl.workspace_rule({ workspace = "f[1]", gaps_out = 0, gaps_in = 0 })

hl.window_rule({
  name        = "no-gaps-wtv1",
  match       = { float = false, workspace = "w[tv1]" },
  border_size = 0,
  rounding    = 0,
})

hl.window_rule({
  name        = "no-gaps-f1",
  match       = { float = false, workspace = "f[1]" },
  border_size = 0,
  rounding    = 0,
})
