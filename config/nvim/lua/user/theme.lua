local scheme = "catppuccin"
local background = "#10101D"

-- Re-applied on every :colorscheme, which otherwise wipes the override.
local function overrides()
  local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
  vim.api.nvim_set_hl(0, "Normal", vim.tbl_extend("force", normal, { bg = background }))
end

vim.api.nvim_create_autocmd("ColorScheme", {
  group = vim.api.nvim_create_augroup("user_theme", { clear = true }),
  callback = overrides,
})

-- The scheme is optional: fall back to the default if it isn't installed.
if not pcall(vim.cmd.colorscheme, scheme) then
  overrides()
end
