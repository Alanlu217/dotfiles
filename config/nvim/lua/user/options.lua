-- Leader must be set before any mapping is created.
vim.g.mapleader = " "
vim.g.maplocalleader = " "

local opt = vim.opt

-- UI
opt.number = true
opt.cursorline = true
opt.signcolumn = "number" -- no separate column; diagnostic signs replace the line number on their line
opt.scrolloff = 8
opt.splitright = true
opt.splitbelow = true
opt.list = true
opt.listchars = { tab = "> ", trail = "-", nbsp = "+" }
opt.breakindent = true
opt.shortmess:append("I")
opt.mouse = "a"
opt.winborder = "solid"

-- Behaviour
opt.timeoutlen = 400
opt.confirm = true
opt.undofile = true
opt.inccommand = "split"
opt.scrollback = 100000

-- Completion (see lua/core/completion): native menu, nothing inserted until accepted.
opt.completeopt = { "menu", "menuone", "noinsert", "popup" }
opt.pumheight = 10
opt.shortmess:append("c") -- no "match 1 of N" / "-- Complete --" messages while typing

-- Search
opt.ignorecase = true
opt.smartcase = true

-- Indentation: 2-space soft tabs
opt.expandtab = true
opt.tabstop = 2
opt.shiftwidth = 2
opt.softtabstop = 2
opt.smartindent = true

-- Spelling
opt.spelllang = "en_au"
