local map = vim.keymap.set

-- Reload: clear cached config modules, then re-run init.lua
map("n", "<leader>R", function()
  for name in pairs(package.loaded) do
    if name:match("^config") then
      package.loaded[name] = nil
    end
  end
  dofile(vim.env.MYVIMRC)
  vim.notify("Config reloaded")
end, { desc = "Reload config" })

map("n", "<leader>f", ":FZF<CR>", { desc = "FZF file picker" })
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
    map({ "n", "t" }, "<A-" .. key .. ">", "<C-\\><C-n><C-w>" .. dir, { desc = "Window " .. dir })
  end
end

-- Clear highlighting on escape
map("n", "<Esc>", "<cmd>nohlsearch<CR>", { desc = "Clear search highlight" })
