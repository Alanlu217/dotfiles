-- reload
vim.keymap.set("n", "<leader>r", ":so<CR>")

-- copy
vim.keymap.set({ "n", "v", "x" }, "<leader>y", '"+y<CR>')
vim.keymap.set({ "n", "v", "x" }, "<leader>d", '"+d<CR>')
vim.keymap.set({ "n", "v", "x" }, "<leader>w", ":w<CR>")
vim.keymap.set({ "n", "v", "x" }, "<leader>q", ":q<CR>")

-- pickers
vim.keymap.set("n", "<leader>f", ":Pick files<CR>")
vim.keymap.set("n", "<leader>e", ":Oil --float<CR>")
vim.keymap.set("n", "<leader>h", ":Pick help<CR>")
