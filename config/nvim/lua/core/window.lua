local M = {}

--- Move the border of the current window in direction `dir` (h/j/k/l).
---@param dir "h"|"j"|"k"|"l"
---@param amount? integer
function M.resize(dir, amount)
  if vim.api.nvim_win_get_config(0).relative ~= "" then
    return
  end
  amount = amount or 2
  local horizontal = dir == "h" or dir == "l"
  local toward_after = dir == "l" or dir == "j" -- right / down
  -- Is there a neighbour on the far side (right for horizontal, below for vertical)?
  local after = horizontal and "l" or "j"
  local has_after = vim.fn.winnr(after) ~= vim.fn.winnr()
  -- With a neighbour after us our far border follows the key; without one only
  -- the near border can move, so the effect flips.
  local grow = toward_after == has_after
  vim.cmd(("%sresize %s%d"):format(horizontal and "vertical " or "", grow and "+" or "-", amount))
end

return M
