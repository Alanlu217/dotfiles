vim.pack.add({ "https://github.com/nvim-mini/mini.nvim" })

require("mini.comment").setup({
	mappings = {
		comment = "<leader>c",
		comment_line = "<leader>c",
		comment_visual = "<leader>c",
		textobject = "<leader>c",
	},
})
require("mini.extra").setup()
require("mini.icons").setup()
require("mini.pairs").setup()
require("mini.pick").setup()
require("mini.surround").setup()
