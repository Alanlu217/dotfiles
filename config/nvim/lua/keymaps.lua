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

-- Window navigation: Alt+hjkl / Alt+arrows, from normal or terminal mode
local arrows = { h = "Left", j = "Down", k = "Up", l = "Right" }
for dir, arrow in pairs(arrows) do
  for _, key in ipairs({ dir, arrow }) do
    map({ "n", "i", "t" }, "<A-" .. key .. ">", "<C-\\><C-n><C-w>" .. dir, { desc = "Window " .. dir })
  end
end

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
map("n", "<leader>c", "gcc", { remap = true, desc = "Toggle comment" })
map("x", "<leader>c", "gc", { remap = true, desc = "Toggle comment" })

-- Clear highlighting on escape
map("n", "<Esc>", "<cmd>nohlsearch<CR>", { desc = "Clear search highlight" })
