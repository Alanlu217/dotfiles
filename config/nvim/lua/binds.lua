-- reload
vim.keymap.set("n", "<leader>R", ":so ~/.config/nvim/init.lua<CR>")

-- copy
vim.keymap.set({ "n", "v", "x" }, "<leader>y", '"+y<CR>')
vim.keymap.set({ "n", "v", "x" }, "<leader>d", '"+d<CR>')
vim.keymap.set({ "n", "v", "x" }, "<leader>w", ":w<CR>")
vim.keymap.set({ "n", "v", "x" }, "<leader>q", ":q<CR>")

-- panes
vim.keymap.set("n", "<leader>x", ":only<CR>")

-- pickers
vim.keymap.set("n", "<leader>f", ":Pick files<CR>")
vim.keymap.set("n", "<leader>e", ":Oil --float<CR>")
vim.keymap.set("n", "<leader>h", ":Pick help<CR>")

-- lsp
vim.keymap.set("n", "gd", vim.lsp.buf.definition)
vim.keymap.set("n", "gD", vim.lsp.buf.declaration)
vim.keymap.set("n", "gi", vim.lsp.buf.implementation)
vim.keymap.set("n", "gr", vim.lsp.buf.references)
vim.keymap.set("n", "gt", vim.lsp.buf.type_definition)
vim.keymap.set("n", "<leader>r", vim.lsp.buf.rename)
vim.keymap.set("n", "<leader>a", vim.lsp.buf.code_action)
