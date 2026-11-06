vim.pack.add { "https://github.com/saghen/blink.cmp" }

require("blink.cmp").build():pwait(60000)

-- Lazy-load the setup on first insert
vim.api.nvim_create_autocmd("InsertEnter", {
  pattern = "*",
  group = require("util").augroup("BlinkCmpLazyLoad"),
  once = true,
  callback = function()
    require("blink.cmp").setup({
      keymap = { preset = "super-tab" },
      appearance = {
        use_nvim_cmp_as_default = true,
      },
      completion = {
        documentation = { auto_show = true },
      },
      sources = {
        default = { "lsp", "path", "snippets", "buffer" },
      },
      fuzzy = { implementation = "prefer_rust_with_warning" },
      signature = { enabled = true },
    })
  end,
})
