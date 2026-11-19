-- Per-monitor workspaces for Hyprland (Lua config, 0.55+)
-- Based on nezu's script (0BSD): https://forum.hypr.land/t/per-monitor-workspaces-in-lua/1579
--
-- Monitor 0 owns workspaces 1-10, monitor 1 owns 11-20, monitor 2 owns 21-30, etc.
-- SUPER+1..0 always switches to "workspace N on the monitor you're currently on".

local workspaces_per_monitor = 10
local wrap_around = false -- wrap when scrolling past first/last workspace

-- Bind each workspace to its monitor (and make the first one the default).
local function create_workspaces(monitor)
  for i = 1, workspaces_per_monitor do
    hl.workspace_rule({
      workspace = tostring(monitor.id * workspaces_per_monitor + i),
      monitor = monitor.name,
      default = (i == 1),
      -- persistent = true, -- uncomment to keep empty workspaces visible in bars
    })
  end
end

for _, monitor in ipairs(hl.get_monitors()) do
  create_workspaces(monitor)
end
hl.on("monitor.added", create_workspaces) -- handle hotplugged monitors

local function get_active_monitor_id()
  local monitor = hl.get_active_monitor()
  return monitor and monitor.id or 0
end

-- Returns the next/previous workspace index (1..N) on the current monitor, or nil at the edge.
local function get_relative_workspace_index(forwards)
  local current = hl.get_active_workspace()
  if not current then return nil end

  local index = current.id % workspaces_per_monitor
  if index == 0 then index = workspaces_per_monitor end

  index = index + (forwards and 1 or -1)
  if index > workspaces_per_monitor then
    return wrap_around and 1 or nil
  elseif index < 1 then
    return wrap_around and workspaces_per_monitor or nil
  end
  return index
end

local function ws_id(monitor_id, index)
  return tostring(monitor_id * workspaces_per_monitor + index)
end

local function activate_workspace(number)
  return function()
    hl.dispatch(hl.dsp.focus({ workspace = ws_id(get_active_monitor_id(), number) }))
  end
end

local function move_to_workspace(number)
  return function()
    hl.dispatch(hl.dsp.window.move({ workspace = ws_id(get_active_monitor_id(), number), follow = true }))
  end
end

local function activate_workspace_relative(forwards)
  return function()
    local index = get_relative_workspace_index(forwards)
    if not index then return end
    hl.dispatch(hl.dsp.focus({ workspace = ws_id(get_active_monitor_id(), index) }))
  end
end

local function move_to_workspace_relative(forwards)
  return function()
    local index = get_relative_workspace_index(forwards)
    if not index then return end
    hl.dispatch(hl.dsp.window.move({ workspace = ws_id(get_active_monitor_id(), index), follow = true }))
  end
end

-- Keybinds: SUPER+1..0 to switch, SUPER+SHIFT+1..0 to move the focused window
for i = 1, math.min(workspaces_per_monitor, 10) do
  local key = tostring(i % 10)
  hl.bind("SUPER + " .. key, activate_workspace(i))
  hl.bind("SUPER + SHIFT + " .. key, move_to_workspace(i))
end

-- Relative navigation
hl.bind("SUPER + mouse_up", activate_workspace_relative(true))
hl.bind("SUPER + mouse_down", activate_workspace_relative(false))
hl.bind("SUPER + CTRL + right", activate_workspace_relative(true))
hl.bind("SUPER + CTRL + left", activate_workspace_relative(false))
hl.bind("SUPER + ALT + right", move_to_workspace_relative(true))
hl.bind("SUPER + ALT + left", move_to_workspace_relative(false))
