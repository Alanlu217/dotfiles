-- Per-monitor workspaces (native, no plugins).
-- Each monitor owns a block of workspace IDs: slot*10 + 1 .. slot*10 + 10.
-- Mod+1..0 / Mod+Shift+1..0 act on the focused monitor's block.

local WS_PER_MONITOR = 10

local function mod(keys)
  return "SUPER + " .. keys
end

-- Slots are keyed by monitor *name* so numbering stays stable if a monitor is
-- unplugged and replugged (monitor.id can change).
local slots, next_slot = {}, 0

local function ws_base(monitor)
  if slots[monitor.name] == nil then
    slots[monitor.name] = next_slot
    next_slot = next_slot + 1
  end
  return slots[monitor.name] * WS_PER_MONITOR
end

local function ws_id(monitor, n)
  return tostring(ws_base(monitor) + n)
end

local function create_workspaces(monitor)
  for i = 1, WS_PER_MONITOR do
    hl.workspace_rule({
      workspace = ws_id(monitor, i),
      monitor   = monitor.name,
      default   = (i == 1),
      -- persistent = true, -- keep all of them alive (shows in waybar etc.)
    })
  end
end

for _, monitor in ipairs(hl.get_monitors()) do
  create_workspaces(monitor)
end
hl.on("monitor.added", create_workspaces)

-- Focus workspace N on the focused monitor.
local function focus_ws(n)
  return function()
    local mon = hl.get_active_monitor()
    if not mon then return end
    hl.dispatch(hl.dsp.focus({ workspace = ws_id(mon, n) }))
  end
end

-- Send the active window to workspace N on the focused monitor (focus stays).
local function move_to_ws(n)
  return function()
    local mon = hl.get_active_monitor()
    if not mon then return end
    hl.dispatch(hl.dsp.window.move({ workspace = ws_id(mon, n), follow = false }))
  end
end

-- Step through this monitor's workspaces (clamped, no wrapping, like niri).
local function focus_relative(delta)
  return function()
    local mon = hl.get_active_monitor()
    if not mon then return end
    local base = ws_base(mon)
    local ws = hl.get_active_workspace()
    local idx = ws and (ws.id - base) or 1
    if idx < 1 or idx > WS_PER_MONITOR then idx = 1 end
    idx = math.max(1, math.min(WS_PER_MONITOR, idx + delta))
    hl.dispatch(hl.dsp.focus({ workspace = tostring(base + idx) }))
  end
end

for n = 1, WS_PER_MONITOR do
  local key = tostring(n % 10) -- workspace 10 is on key 0
  hl.bind(mod(key), focus_ws(n))
  hl.bind(mod("SHIFT + " .. key), move_to_ws(n))
end

-- Workspace up/down: Mod+Ctrl+W/S/Up/Down, Mod+I/U, Mod+wheel (same as niri)
local relative_keys = {
  [-1] = { "CTRL + W", "CTRL + up", "I", "mouse_up" },
  [1]  = { "CTRL + S", "CTRL + down", "U", "mouse_down" },
}

for delta, keys in pairs(relative_keys) do
  for _, key in ipairs(keys) do
    hl.bind(mod(key), focus_relative(delta))
  end
end
