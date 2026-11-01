vim.pack.add{
  "https://github.com/saghen/blink.lib",
  "https://github.com/saghen/blink.cmp",
  "https://github.com/saghen/blink.pairs",
  "https://github.com/saghen/blink.indent",
}

require('blink.cmp').build():pwait(60000)
require('blink.pairs').build():pwait(60000)

require('blink.pairs').setup()

local group = vim.api.nvim_create_augroup("BlinkCmpLazyLoad", { clear = true })

vim.api.nvim_create_autocmd("InsertEnter", {
	pattern = "*",
	group = group,
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
		})
	end,
})

