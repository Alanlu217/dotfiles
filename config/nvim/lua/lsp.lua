vim.pack.add({
	"https://github.com/neovim/nvim-lspconfig",
	"https://github.com/saghen/blink.cmp",
	"https://github.com/stevearc/conform.nvim",
})

vim.lsp.enable({ "gopls", "clangd", "zls", "rust-analyzer" })

require("blink.cmp").setup({
	keymap = {
		preset = "enter",

		["<Tab>"] = {
			"insert_next",
			"snippet_forward",
			"fallback",
		},
		["<S-Tab>"] = { "insert_prev", "snippet_backward", "fallback" },
	},
	completion = {
		list = { selection = { preselect = false } },
		documentation = { auto_show = true, auto_show_delay_ms = 500 },
	},
	sources = {
		default = { "lsp", "path", "snippets", "buffer" },
	},
	fuzzy = { implementation = "lua" },
})
