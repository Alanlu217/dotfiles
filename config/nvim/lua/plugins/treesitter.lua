vim.pack.add({ "https://github.com/nvim-treesitter/nvim-treesitter" })

require("nvim-treesitter.configs").setup({
	ensure_installed = {
		"c",
		"cpp",
		"css",
		"csv",
		"dockerfile",
		"fish",
		"gitcommit",
		"gitignore",
		"go",
		"html",
		"javascript",
		"json",
		"latex",
		"lua",
		"markdown",
		"python",
		"rust",
		"toml",
		"typescript",
		"yaml",
		"zig",
	},
    ignore_install = { "verilog" },
	auto_install = true,
	highlight = {
		enable = true,
	},
	indent = {
		enable = true,
	},
})
