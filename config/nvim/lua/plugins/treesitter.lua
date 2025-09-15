vim.pack.add({ "https://github.com/nvim-treesitter/nvim-treesitter" })

require("nvim-treesitter.configs").setup({
	ensure_installed = {
		"c",
		"css",
		"gitignore",
		"html",
		"javascript",
		"json",
		"lua",
		"markdown",
		"python",
		"rust",
		"toml",
		"typescript",
		"yaml",
		"cpp",
		"csv",
		"dockerfile",
		"fish",
		"gitcommit",
		"go",
		"zig",
	},
	auto_install = true,
	highlight = {
		enable = true,
	},
	indent = {
		enable = true,
	},
})
