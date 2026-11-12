-- Bootstrap only. Nothing personal lives here.
--
--   lua/core/  framework: native bridge, picker, terminal, window helpers.
--              Provides mechanisms; defines no options and no keymaps.
--   lua/user/  your space: options, theme, keymaps, per-feature settings.
--   native/    C sources (built out-of-tree into stdpath("data")/native).

if vim.fn.has("nvim-0.11") == 0 then
  vim.api.nvim_echo({ { "This config requires Neovim >= 0.11", "ErrorMsg" } }, true, {})
  return
end

require("core").start()
