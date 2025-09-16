-- leader key
vim.g.mapleader = " "

-- disable netrw
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

-- disable swapfiles
vim.opt.swapfile = false

-- indent
vim.opt.autoindent = true
vim.opt.expandtab = true
vim.opt.shiftwidth = 4
vim.opt.smarttab = true
vim.opt.tabstop = 4

-- wrapping
vim.opt.shiftround = true
vim.opt.wrap = true
vim.opt.signcolumn = "yes"
vim.opt.winborder = "double"

-- numbers
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.ruler = true

-- fold settings
vim.opt.foldcolumn = "0"
vim.opt.foldlevel = 99
vim.opt.foldenable = true

-- search
vim.opt.hlsearch = true
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.incsearch = true

-- errors
vim.opt.visualbell = false
