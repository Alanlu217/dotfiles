vim.pack.add({
	"https://github.com/neovim/nvim-lspconfig",
	"https://github.com/saghen/blink.cmp",
	"https://github.com/stevearc/conform.nvim",
})

vim.lsp.enable({ "gopls", "clangd", "zls", "rust_analyzer", "texlab", "tinymist", "pyrefly", "ruff", "verible" })

require("blink.cmp").setup({
	keymap = {
		preset = "super-tab",
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

require("conform").setup({
    formatters_by_ft = {
        lua = { "stylua" },
        go = { "goimports" },
        rust = { "rustfmt" },
        zig = { "zigfmt" },
        typst = { "typstyle" },
        python = { "ruff_format" },
        verilog = { "verible" },
    },
    formatters = {
        verible = {
            prepend_args = { "--indentation_spaces=4", "--wrap_spaces=4" },
        },
    },
})

vim.api.nvim_create_autocmd("BufWritePre", {
	pattern = "*",
	callback = function(args)
		require("conform").format({ bufnr = args.buf })
	end,
})
