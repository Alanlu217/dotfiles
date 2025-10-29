vim.pack.add({
	"https://github.com/neovim/nvim-lspconfig",
	"https://github.com/saghen/blink.cmp",
	"https://github.com/stevearc/conform.nvim",
})

vim.lsp.enable({ "gopls", "clangd", "zls", "rust_analyzer", "texlab", "tinymist", "ty", "ruff" })

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

vim.api.nvim_create_autocmd("FileType", {
	pattern = "typst",
	callback = function()
		MiniPairs.map("i", "$", { action = "closeopen", pair = "$$", neigh_pattern = "[^\\]." })
	end,
})
