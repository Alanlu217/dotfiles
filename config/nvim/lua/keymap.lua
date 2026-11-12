local map = vim.keymap.set

-- Reload: clear cached modules that live in this config, then re-run init.lua
map("n", "<leader>R", function()
  local lua_dir = vim.fn.stdpath("config") .. "/lua/"
  for name in pairs(package.loaded) do
    local rel = name:gsub("%.", "/")
    if vim.uv.fs_stat(lua_dir .. rel .. ".lua") or vim.uv.fs_stat(lua_dir .. rel .. "/init.lua") then
      package.loaded[name] = nil
    end
  end
  dofile(vim.env.MYVIMRC)
  vim.notify("Config reloaded")
end, { desc = "Reload config" })

map("n", "<C-a>", "ggVG", { desc = "Select whole file" })

-- System clipboard
map({ "n", "v" }, "<leader>y", [["+y]], { desc = "Yank to system clipboard" })
map("n", "<leader>Y", [["+Y]], { desc = "Yank line to system clipboard" })
map({ "n", "v" }, "<leader>p", [["+p]], { desc = "Paste from system clipboard" })
map({ "n", "v" }, "<leader>P", [["+P]], { desc = "Paste before from system clipboard" })

-- Terminal
map("t", "<Esc><Esc>", [[<C-\><C-n>]], { desc = "Exit terminal mode" })
map("n", "<leader>x", ":botright 15split | terminal<CR>", { desc = "Terminal (bottom)" })
map("n", "<leader>X", ":botright vsplit | terminal<CR>", { desc = "Terminal (right)" })

-- Window navigation: Alt+hjkl / Alt+arrows, from normal or terminal mode
local arrows = { h = "Left", j = "Down", k = "Up", l = "Right" }
for dir, arrow in pairs(arrows) do
  for _, key in ipairs({ dir, arrow }) do
    map({ "n", "i", "t" }, "<A-" .. key .. ">", "<C-\\><C-n><C-w>" .. dir, { desc = "Window " .. dir })
  end
end

-- Window resizing: Ctrl+arrows / Ctrl+Shift+hjkl move the border in that direction
local function resize(dir, amount)
  amount = amount or 2
  local horizontal = dir == "h" or dir == "l"
  local toward_after = dir == "l" or dir == "j" -- right/down
  -- is there a window to the right (horizontal) or below (vertical)?
  local has_after = vim.fn.winnr(horizontal and "l" or "j") ~= vim.fn.winnr()
  -- With a neighbour after us, our far border moves with the key; without one,
  -- only our near border can move, so the direction flips.
  local grow = toward_after == has_after
  vim.cmd(string.format("%sresize %s%d", horizontal and "vertical " or "", grow and "+" or "-", amount))
end

local resize_keys = {
  h = { "<C-Left>",  "<C-S-h>" },
  j = { "<C-Down>",  "<C-S-j>" },
  k = { "<C-Up>",    "<C-S-k>" },
  l = { "<C-Right>", "<C-S-l>" },
}
for dir, keys in pairs(resize_keys) do
  for _, key in ipairs(keys) do
    map({ "n", "t" }, key, function() resize(dir) end, { desc = "Resize window " .. dir })
  end
end

map("n", "<leader>w", "<C-w>", { remap = false, desc = "Window commands" })

-- Tab navigation: Shift+Alt+h/l or Shift+Alt+Left/Right
local tab_keys = {
  { keys = { "<A-H>", "<A-S-Left>" },  cmd = "tabprevious", desc = "Previous tab" },
  { keys = { "<A-L>", "<A-S-Right>" }, cmd = "tabnext",     desc = "Next tab" },
}
for _, t in ipairs(tab_keys) do
  for _, key in ipairs(t.keys) do
    map({ "n", "i", "t" }, key, "<C-\\><C-n><cmd>" .. t.cmd .. "<CR>", { desc = t.desc })
  end
end

-- Tab management
map("n", "<leader>tn", "<cmd>tabnew<CR>", { desc = "New tab" })
map("n", "<leader>tc", "<cmd>tabclose<CR>", { desc = "Close tab" })
map("n", "<leader>to", "<cmd>tabonly<CR>", { desc = "Close other tabs" })
map({ "n", "i", "t" }, "<A-t>", "<C-\\><C-n><cmd>tabnew<CR>", { desc = "New tab" })

-- Toggle comment (built-in gc / gcc, so remap = true)
map({"n", "x"}, "<leader>c", "gcc", { remap = true, desc = "Toggle comment" })

-- Clear highlighting on escape
map("n", "<Esc>", "<cmd>nohlsearch<CR>", { desc = "Clear search highlight" })

-- Toggle Spellcheck
vim.keymap.set("n", "<leader>us", function()
  local enabled = not vim.b.spell_enabled
  vim.b.spell_enabled = enabled
  vim.wo.spell = enabled
  vim.notify("Spell check " .. (enabled and "on" or "off"))
end, { desc = "Toggle spell check (buffer)" })

vim.api.nvim_create_autocmd("BufWinEnter", {
  group = vim.api.nvim_create_augroup("buffer_local_spell", { clear = true }),
  callback = function(ev)
    vim.wo.spell = vim.b[ev.buf].spell_enabled == true
  end,
})

