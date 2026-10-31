-- leader
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- colourscheme
pcall(vim.cmd.colorscheme, "catppuccin")

-- options
vim.opt.number = true
vim.opt.timeoutlen = 400
vim.opt.scrollback = 100000
vim.opt.mouse = "a"

-- soft tabs
vim.opt.expandtab = true     -- soft tabs (spaces)
vim.opt.tabstop = 4          -- how a literal tab is displayed
vim.opt.shiftwidth = 4       -- indent size for >>, <<, autoindent
vim.opt.softtabstop = 4      -- <Tab>/<BS> in insert mode act like 4 spaces
vim.opt.smartindent = true   -- sensible auto-indent for C-like code

-- Makefiles need real tabs
vim.api.nvim_create_autocmd("FileType", {
  pattern = "make",
  callback = function() vim.opt_local.expandtab = false end,
})


-- keybinds
vim.keymap.set("n", "<leader>R", [[:so $MYVIMRC<CR>]], { desc = "Reload Config" })
vim.keymap.set("t", "<Esc><Esc>", [[<C-\><C-n>]], { desc = "Exit terminal mode" })
vim.keymap.set("n", "<leader>f", [[:FZF<CR>]], { desc = "Open FZF file picker" })
vim.keymap.set("n", "<C-a>", [[ggVG]], { desc = "Select whole file" })

vim.keymap.set({ "n", "v" }, "<leader>y", [["+y]], { desc = "Yank to system clipboard" })
vim.keymap.set("n", "<leader>Y", [["+Y]], { desc = "Yank line to system clipboard" })
vim.keymap.set({ "n", "v" }, "<leader>p", [["+p]], { desc = "Paste from system clipboard" })
vim.keymap.set({ "n", "v" }, "<leader>P", [["+P]], { desc = "Paste before from system clipboard" })

local dirs = {
  h = { "h", "<A-Left>" },
  j = { "j", "<A-Down>" },
  k = { "k", "<A-Up>" },
  l = { "l", "<A-Right>" },
}

for dir, keys in pairs(dirs) do
  local alt_vi = "<A-" .. keys[1] .. ">"
  local alt_arrow = keys[2]
  for _, lhs in ipairs({ alt_vi, alt_arrow }) do
    vim.keymap.set("t", lhs, "<C-\\><C-n><C-w>" .. dir, { desc = "Window " .. dir })
    vim.keymap.set("n", lhs, "<C-w>" .. dir, { desc = "Window " .. dir })
  end
end

vim.keymap.set("n", "<leader>tt", "<cmd>botright 15split | terminal<CR>", { desc = "Terminal (bottom)" })
vim.keymap.set("n", "<leader>tv", "<cmd>vsplit | terminal<CR>", { desc = "Terminal (vertical)" })

-- lsp
vim.lsp.config("tinymist", {
  cmd = { "tinymist" },
  filetypes = { "typst" },
  root_markers = { ".git" },
})

-- Only enable servers whose binary exists (handy across NixOS and Arch)
local function enable_if_installed(name, bin)
  if vim.fn.executable(bin or name) == 1 then
    vim.lsp.enable(name)
  end
end

enable_if_installed("tinymist")

vim.diagnostic.config({
  virtual_text = true,
  severity_sort = true,
  float = { border = "rounded" },
})

-- Keymaps only when a server attaches
vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(ev)
    local map = function(keys, fn, desc)
      vim.keymap.set("n", keys, fn, { buffer = ev.buf, desc = desc })
    end
    map("gd", vim.lsp.buf.definition, "Go to definition")
    map("gr", vim.lsp.buf.references, "References")
    map("K", vim.lsp.buf.hover, "Hover")
    map("<leader>rn", vim.lsp.buf.rename, "Rename")
    map("<leader>ca", vim.lsp.buf.code_action, "Code action")
    map("<leader>d", vim.diagnostic.open_float, "Line diagnostics")
    map("[d", function() vim.diagnostic.jump({ count = -1 }) end, "Prev diagnostic")
    map("]d", function() vim.diagnostic.jump({ count = 1 }) end, "Next diagnostic")
    map("<leader>F", function() vim.lsp.buf.format({ async = true }) end, "Format")
  end,
})

-- Typst buffers: wrap and spellcheck
vim.api.nvim_create_autocmd("FileType", {
  pattern = "typst",
  callback = function()
    vim.opt_local.wrap = true
    vim.opt_local.linebreak = true
    vim.opt_local.spell = true
    vim.opt_local.spelllang = "en_au"
  end,
})
