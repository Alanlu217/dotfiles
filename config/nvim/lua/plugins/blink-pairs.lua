vim.pack.add { "https://github.com/saghen/blink.pairs" }

require("blink.pairs").build():pwait(60000)

require("blink.pairs").setup({
  mappings = { cmdline = false, },
})
