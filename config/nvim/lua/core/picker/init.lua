-- Public picker API:
--   require("core.picker").files() / .buffers() / .recent() / .help()
--   require("core.picker").symbols() / .workspace_symbols()   -- LSP
--   require("core.picker").diagnostics() / .buffer_diagnostics()
--   require("core.picker").keymaps()
--   require("core.picker").open({ title, matcher, on_select, on_cancel? })
--   require("core.picker").select(items, opts, on_choice)   -- vim.ui.select
--   :Pick files|buffers|recent|help|symbols|workspace_symbols|diagnostics|buffer_diagnostics|keymaps
local M = {}

---@param spec core.picker.Spec
function M.open(spec)
  require("core.picker.ui").open(spec)
end

---@param opts? { root?: string }
function M.files(opts)
  require("core.picker.sources").files(opts)
end

function M.buffers()
  require("core.picker.sources").buffers()
end

function M.recent()
  require("core.picker.sources").recent()
end

function M.help()
  require("core.picker.sources").help()
end

--- Symbols of the current file (LSP).
function M.symbols()
  require("core.picker.symbols").document()
end

--- Symbols across the workspace (LSP).
function M.workspace_symbols()
  require("core.picker.symbols").workspace()
end

--- Diagnostics of every open buffer.
function M.diagnostics()
  require("core.picker.diagnostics").open()
end

--- Diagnostics of the current buffer.
function M.buffer_diagnostics()
  require("core.picker.diagnostics").open({ buffer = true })
end

--- Every keymap that applies to the current buffer.
function M.keymaps()
  require("core.picker.keymaps").open()
end

---@param items string[] one entry per line, no newlines inside
---@return core.Matcher
function M.matcher(items)
  return require("core.picker.matcher").from_list(items)
end

--- vim.ui.select implementation backed by the picker.
---@generic T
---@param items T[]
---@param opts? { prompt?: string, format_item?: fun(item: T): string }
---@param on_choice fun(item: T?, idx: integer?)
function M.select(items, opts, on_choice)
  opts = opts or {}
  if #items == 0 then
    on_choice(nil, nil)
    return
  end

  local format = opts.format_item or tostring
  local labels, lookup, seen = {}, {}, {}
  for i, item in ipairs(items) do
    local label = (tostring(format(item)):gsub("[\r\n]+", " "))
    seen[label] = (seen[label] or 0) + 1
    if seen[label] > 1 then
      label = ("%s [%d]"):format(label, seen[label])
    end
    labels[i] = label
    lookup[label] = i
  end

  M.open({
    title = (tostring(opts.prompt or "Select"):gsub(":%s*$", "")),
    matcher = M.matcher(labels),
    on_select = function(label)
      local idx = lookup[label]
      on_choice(items[idx], idx)
    end,
    on_cancel = function()
      on_choice(nil, nil)
    end,
  })
end

function M.setup()
  if require("core.config").get().picker.override_ui_select then
    vim.ui.select = M.select
  end

  local names = {
    "files",
    "buffers",
    "recent",
    "help",
    "symbols",
    "workspace_symbols",
    "diagnostics",
    "buffer_diagnostics",
    "keymaps",
  }
  vim.api.nvim_create_user_command("Pick", function(o)
    local name = o.args ~= "" and o.args or "files"
    if vim.tbl_contains(names, name) then
      M[name]()
    else
      vim.notify("Pick: unknown source '" .. o.args .. "'", vim.log.levels.ERROR)
    end
  end, {
    nargs = "?",
    complete = function()
      return names
    end,
    desc = "Open a picker (files|buffers|recent|help|symbols|workspace_symbols|diagnostics|buffer_diagnostics|keymaps)",
  })
end

return M
