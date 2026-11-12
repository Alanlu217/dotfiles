local M = {}

---@param msg string
---@param level? integer
function M.notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = "config" })
end

--- require() that never throws: failures are reported once the UI is up.
---@param mod string
---@return boolean ok, any result
function M.safe_require(mod)
  local ok, res = pcall(require, mod)
  if not ok then
    vim.schedule(function()
      M.notify(("Failed to load '%s':\n%s"):format(mod, res), vim.log.levels.ERROR)
    end)
  end
  return ok, res
end

---@param name string
---@return integer
function M.augroup(name)
  return vim.api.nvim_create_augroup("config_" .. name, { clear = true })
end

--- Recursive merge; lists and scalars from `over` replace those in `base`.
---@param base table
---@param over table
---@return table
function M.deep_merge(base, over)
  local out = vim.deepcopy(base)
  for k, v in pairs(over) do
    if type(v) == "table" and type(out[k]) == "table" and not vim.islist(v) then
      out[k] = M.deep_merge(out[k], v)
    else
      out[k] = vim.deepcopy(v)
    end
  end
  return out
end

return M
