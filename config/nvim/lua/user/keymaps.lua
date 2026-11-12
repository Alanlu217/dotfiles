local map = vim.keymap.set

-- General -------------------------------------------------------------------
map("n", "<leader>R", "<cmd>ReloadConfig<CR>", { desc = "Reload config" })
-- Note: shadows the built-in <C-a> number increment.
map("n", "<C-a>", "ggVG", { desc = "Select whole file" })
map("n", "<Esc>", "<cmd>nohlsearch<CR>", { desc = "Clear search highlight" })
-- Built-in gc / gcc, so remap = true. Visual mode needs `gc`, not `gcc`.
map("n", "<leader>c", "gcc", { remap = true, desc = "Toggle comment" })
map("x", "<leader>c", "gc", { remap = true, desc = "Toggle comment" })

-- Picker --------------------------------------------------------------------
map({ "n", "v" }, "<leader>f", function() require("core.picker").files() end, { desc = "Pick files" })
map({ "n", "v" }, "<leader>b", function() require("core.picker").buffers() end, { desc = "Pick buffers" })
map({ "n", "v" }, "<leader>r", function() require("core.picker").recent() end, { desc = "Pick recent files" })

-- System clipboard ----------------------------------------------------------
map({ "n", "v" }, "<leader>y", [["+y]], { desc = "Yank to system clipboard" })
map("n", "<leader>Y", [["+Y]], { desc = "Yank line to system clipboard" })
map({ "n", "v" }, "<leader>p", [["+p]], { desc = "Paste from system clipboard" })
map({ "n", "v" }, "<leader>P", [["+P]], { desc = "Paste before from system clipboard" })

-- Terminal ------------------------------------------------------------------
map("t", "<Esc><Esc>", [[<C-\><C-n>]], { desc = "Exit terminal mode" })
map("n", "<leader>x", function() require("core.terminal").open("bottom") end, { desc = "Terminal (bottom)" })
map("n", "<leader>X", function() require("core.terminal").open("right") end, { desc = "Terminal (right)" })
-- Note: mapping <C-\> means a typed <C-\><C-n> no longer works; use <Esc><Esc>.
map({ "n", "t" }, "<C-\\>", function() require("core.terminal").toggle_float() end, { desc = "Terminal (floating)" })

-- Windows -------------------------------------------------------------------
map("n", "<leader>w", "<C-w>", { remap = false, desc = "Window commands" })

-- Focus: Alt+hjkl / Alt+arrows from normal, insert or terminal mode.
local arrows = { h = "Left", j = "Down", k = "Up", l = "Right" }
for dir, arrow in pairs(arrows) do
  for _, key in ipairs({ dir, arrow }) do
    map({ "n", "i", "t" }, "<A-" .. key .. ">", "<C-\\><C-n><C-w>" .. dir, { desc = "Window " .. dir })
  end
end

-- Resize: Ctrl+arrows / Ctrl+Shift+hjkl move the border in that direction.
-- (Ctrl+Shift+letter needs a terminal with the kitty keyboard protocol.)
local resize_keys = {
  h = { "<C-Left>", "<C-S-h>" },
  j = { "<C-Down>", "<C-S-j>" },
  k = { "<C-Up>", "<C-S-k>" },
  l = { "<C-Right>", "<C-S-l>" },
}
for dir, keys in pairs(resize_keys) do
  for _, key in ipairs(keys) do
    map({ "n", "t" }, key, function() require("core.window").resize(dir) end, { desc = "Resize window " .. dir })
  end
end

-- Tabs ----------------------------------------------------------------------
local tab_nav = {
  { keys = { "<A-H>", "<A-S-Left>" }, cmd = "tabprevious", desc = "Previous tab" },
  { keys = { "<A-L>", "<A-S-Right>" }, cmd = "tabnext", desc = "Next tab" },
}
for _, t in ipairs(tab_nav) do
  for _, key in ipairs(t.keys) do
    map({ "n", "i", "t" }, key, "<C-\\><C-n><cmd>" .. t.cmd .. "<CR>", { desc = t.desc })
  end
end

map("n", "<leader>tn", "<cmd>tabnew<CR>", { desc = "New tab" })
map("n", "<leader>tc", "<cmd>tabclose<CR>", { desc = "Close tab" })
map("n", "<leader>to", "<cmd>tabonly<CR>", { desc = "Close other tabs" })
map({ "n", "i", "t" }, "<A-t>", "<C-\\><C-n><cmd>tabnew<CR>", { desc = "New tab" })
