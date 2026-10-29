vim.g.mapleader = " "
vim.opt.timeoutlen = 300

vim.keymap.set("n", "<leader>R", [[:so $MYVIMRC<CR>]], { desc = "Reload Config" })
vim.keymap.set("t", "<Esc><Esc>", [[<C-\><C-n>]], { desc = "Exit terminal mode" })
vim.keymap.set("n", "<leader>f", [[:FZF<CR>]], { desc = "Open FZF file picker" })

vim.keymap.set({ "n", "v" }, "<leader>y", [["+y]], { desc = "Yank to system clipboard" })
vim.keymap.set("n", "<leader>Y", [["+Y]], { desc = "Yank line to system clipboard" })
vim.keymap.set({ "n", "v" }, "<leader>p", [["+p]], { desc = "Paste from system clipboard" })
vim.keymap.set({ "n", "v" }, "<leader>P", [["+P]], { desc = "Paste before from system clipboard" })

vim.cmd.colorscheme("catppuccin")
