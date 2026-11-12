local opt = vim.opt

opt.number = true
opt.mouse = "a"
opt.timeoutlen = 400
opt.scrollback = 100000
opt.signcolumn = "yes"
opt.shortmess:append("I")
opt.ignorecase = true
opt.smartcase = true
opt.undofile = true
opt.splitright = true
opt.splitbelow = true
opt.cursorline = true
opt.scrolloff = 8
opt.inccommand = "split"
opt.confirm = true
opt.breakindent = true
opt.list = true
opt.listchars = { tab = "» ", trail = "·", nbsp = "␣" }
opt.spelllang = "en_au"

-- Indentation: 2-space soft tabs
opt.expandtab = true
opt.tabstop = 2
opt.shiftwidth = 2
opt.softtabstop = 2
opt.smartindent = true

-- Colour Theme
pcall(vim.cmd.colorscheme, "catppuccin")
vim.api.nvim_set_hl(0, "Normal", { bg = "#10101D" })

