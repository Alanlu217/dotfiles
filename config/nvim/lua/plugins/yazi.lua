vim.pack.add { "https://github.com/mikavilpas/yazi.nvim" }
vim.pack.add { "https://github.com/nvim-lua/plenary.nvim" }

require("yazi").setup({
  open_for_directories = true,
  change_neovim_cwd_on_close = true,
})

vim.keymap.set("n", "<leader>e", "<cmd>Yazi<cr>", { desc = "Open yazi at current file" })
vim.keymap.set("n", "<leader>E", "<cmd>Yazi cwd<cr>", { desc = "Open yazi in cwd" })
