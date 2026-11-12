-- Leader must be set before any mapping is created.
vim.g.mapleader = " "
vim.g.maplocalleader = " "

local opt = vim.opt

-- UI
opt.number = true
opt.cursorline = true
opt.signcolumn = "yes"
opt.scrolloff = 8
opt.splitright = true
opt.splitbelow = true
opt.list = true
opt.listchars = { tab = "> ", trail = "-", nbsp = "+" }
opt.breakindent = true
opt.shortmess:append("I")
opt.mouse = "a"

-- Behaviour
opt.timeoutlen = 400
opt.confirm = true
opt.undofile = true
opt.inccommand = "split"
opt.scrollback = 100000

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
