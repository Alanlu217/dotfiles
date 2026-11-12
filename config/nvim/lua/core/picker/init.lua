-- Public picker API:
--   require("core.picker").files() / .buffers() / .recent()
--   require("core.picker").open({ title, matcher, on_select })   -- custom sources
--   :Pick files|buffers|recent
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

---@param items string[] one entry per line, no newlines inside
---@return core.Matcher
function M.matcher(items)
  return require("core.picker.matcher").from_list(items)
end

function M.setup()
  local names = { "files", "buffers", "recent" }
  vim.api.nvim_create_user_command("Pick", function(o)
    local source = M[o.args ~= "" and o.args or "files"]
    if vim.tbl_contains(names, o.args ~= "" and o.args or "files") and source then
      source()
    else
      vim.notify("Pick: unknown source '" .. o.args .. "'", vim.log.levels.ERROR)
    end
  end, {
    nargs = "?",
    complete = function()
      return names
    end,
    desc = "Open a picker (files|buffers|recent)",
  })
end

return M
