-- reload
vim.keymap.set("n", "<leader>R", ":so ~/.config/nvim/init.lua<CR>", {desc = 'Reload Config'})

-- movement
vim.keymap.set({ "n", "v" }, "<Up>", "gk", { noremap = true, silent = true })
vim.keymap.set({ "n", "v" }, "<Down>", "gj", { noremap = true, silent = true })

-- copy
vim.keymap.set({ "n", "v", "x" }, "<leader>y", '"+y<CR>', { desc = 'Copy to System Clipboard' })
vim.keymap.set({ "n", "v", "x" }, "<leader>p", '"+p<CR>', { desc = 'Paste from System Clipboard' })
vim.keymap.set({ "n", "v", "x" }, "<leader>w", ":w<CR>", { desc = 'Save file' })
vim.keymap.set({ "n", "v", "x" }, "<leader>q", ":q<CR>", { desc = 'Exit Nvim' })

-- windows
vim.keymap.set("n", "<leader>x", ":only<CR>", { desc = 'Close others' })

-- pickers
vim.keymap.set("n", "<leader>f", ":Pick files<CR>", { desc = 'Pick Files' })
vim.keymap.set("n", "<leader>e", ":Oil<CR>", { desc = 'Oil' })

vim.keymap.set("n", "<leader>h", ":Pick help<CR>", { desc = 'Pick Help' })

vim.keymap.set("n", "<leader>s", ':Pick lsp scope="document_symbol"<CR>', { desc = 'Pick Document Symbols' })
vim.keymap.set("n", "<leader>S", ':Pick lsp scope="workspace_symbol"<CR>', { desc = 'Pick Workspace Symbols' })
vim.keymap.set("n", "<leader>D", ":Pick diagnostic<CR>", { desc = 'Pick Diagnostics' })
vim.keymap.set("n", "<leader>d", ":lua vim.diagnostic.open_float()<CR>", { desc = 'Open Diagnostics' })

vim.keymap.set("n", "<leader>C", ":Pick commands<CR>", { desc = 'Pick Commands' })

-- lsp
vim.keymap.set("n", "gd", vim.lsp.buf.definition)
vim.keymap.set("n", "gD", vim.lsp.buf.declaration)
vim.keymap.set("n", "gi", vim.lsp.buf.implementation)
vim.keymap.set("n", "gr", vim.lsp.buf.references)
vim.keymap.set("n", "gt", vim.lsp.buf.type_definition)
vim.keymap.set("n", "<leader>r", vim.lsp.buf.rename)
vim.keymap.set("n", "<leader>a", vim.lsp.buf.code_action)
