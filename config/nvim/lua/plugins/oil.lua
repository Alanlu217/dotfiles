vim.pack.add({ "https://github.com/stevearc/oil.nvim" })

require("oil").setup({
	keymaps = {
		["q"] = { "actions.close", mode = "n" },
		["<ESC>"] = { "actions.close", mode = "n" },
	},
})
