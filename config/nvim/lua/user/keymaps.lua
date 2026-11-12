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
map({ "n", "v" }, "<leader>h", function() require("core.picker").help() end, { desc = "Pick help tags" })

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

local arrows = { h = "Left", j = "Down", k = "Up", l = "Right" }

for dir, arrow in pairs(arrows) do
  -- Focus: Ctrl+hjkl (normal, terminal) and Ctrl+arrows (also insert).
  local focus = "<C-\\><C-n><C-w>" .. dir
  map({ "n", "t" }, "<C-" .. dir .. ">", focus, { desc = "Focus window " .. dir })
  map({ "n", "i", "t" }, "<C-" .. arrow .. ">", focus, { desc = "Focus window " .. dir })

  -- Resize: Ctrl+Alt+hjkl / Ctrl+Alt+arrows move the border in that direction.
  local function resize()
    require("core.window").resize(dir)
  end
  map({ "n", "t" }, "<C-A-" .. dir .. ">", resize, { desc = "Resize window " .. dir })
  map({ "n", "t" }, "<C-A-" .. arrow .. ">", resize, { desc = "Resize window " .. dir })
end

-- Tabs ----------------------------------------------------------------------
-- Alt+h / Alt+l switch tabs, from any mode (Alt+arrows don't work in a tty).
map({ "n", "i", "t" }, "<A-h>", "<C-\\><C-n><cmd>tabprevious<CR>", { desc = "Previous tab" })
map({ "n", "i", "t" }, "<A-l>", "<C-\\><C-n><cmd>tabnext<CR>", { desc = "Next tab" })

map("n", "<leader>tn", "<cmd>tabnew<CR>", { desc = "New tab" })
map("n", "<leader>tc", "<cmd>tabclose<CR>", { desc = "Close tab" })
map("n", "<leader>to", "<cmd>tabonly<CR>", { desc = "Close other tabs" })
map({ "n", "i", "t" }, "<A-t>", "<C-\\><C-n><cmd>tabnew<CR>", { desc = "New tab" })
