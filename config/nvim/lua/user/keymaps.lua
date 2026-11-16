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
map({ "n", "v" }, "<leader>s", function() require("core.picker").symbols() end, { desc = "Pick file symbols" })
map({ "n", "v" }, "<leader>S", function() require("core.picker").workspace_symbols() end,
  { desc = "Pick workspace symbols" })
map({ "n", "v" }, "<leader>d", function() require("core.picker").diagnostics() end,
  { desc = "Pick diagnostics (open buffers)" })
map({ "n", "v" }, "<leader>D", function() require("core.picker").buffer_diagnostics() end,
  { desc = "Pick diagnostics (buffer)" })
map({ "n", "v" }, "<leader>k", function() require("core.picker").keymaps() end, { desc = "Pick keymaps" })

-- Projects (lua/core/projects.lua) ------------------------------------------
-- <leader>o rather than <leader>p, which would delay the clipboard paste below.
-- In the picker <C-t> opens the project in a new tab, <C-s>/<C-v> in a split.
map("n", "<leader>oo", function() require("core.projects").switch("global") end, { desc = "Project (global)" })
map("n", "<leader>ot", function() require("core.projects").switch("tab") end, { desc = "Project (tab)" })
map("n", "<leader>ow", function() require("core.projects").switch("window") end, { desc = "Project (window)" })
map("n", "<leader>oa", function() require("core.projects").add() end, { desc = "Save cwd as project" })
map("n", "<leader>od", function() require("core.projects").remove() end, { desc = "Remove project" })

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
map({ "n", "i", "t" }, "<C-\\>", function() require("core.terminal").toggle_float() end, { desc = "Terminal (floating)" })

-- Completion --------------------------------------------------------------
-- <CR> accepts the highlighted entry; <Tab>/<S-Tab> move through entries without
-- editing the text; arrows are plain cursor keys. <C-n>/<C-p> also move.
-- The <expr> functions fall back to the key's normal action when idle
-- (<Tab>/<S-Tab> then jump between snippet stops).
local function cmp_expr(name)
  return function()
    return require("core.completion")[name]()
  end
end
map("i", "<CR>", cmp_expr("enter"), { expr = true, desc = "Accept completion / newline" })
map("i", "<Tab>", cmp_expr("tab"), { expr = true, desc = "Next completion / next snippet stop / Tab" })
map("i", "<S-Tab>", cmp_expr("s_tab"), { expr = true, desc = "Previous completion / previous snippet stop" })
map("i", "<Up>", cmp_expr("up"), { expr = true, desc = "Up (closes completion)" })
map("i", "<Down>", cmp_expr("down"), { expr = true, desc = "Down (closes completion)" })
map("i", "<C-y>", cmp_expr("confirm"), { expr = true, desc = "Accept completion" })
map("i", "<C-e>", cmp_expr("cancel"), { expr = true, desc = "Close completion" })
local function open_menu()
  require("core.completion").trigger()
end
map("i", "<C-Space>", open_menu, { desc = "Open completion" })
map("i", "<C-@>", open_menu, { desc = "Open completion" }) -- what most terminals send for Ctrl+Space

-- Parameter viewer (lua/core/signature.lua): opens by itself on "(" and ","; these
-- keys open/close it by hand and step through overloads while it is showing.
-- Note: <C-s> shadows Neovim's built-in insert-mode signature help.
map("i", "<C-s>", function() require("core.signature").toggle() end, { desc = "Toggle parameter viewer" })
map("i", "<A-n>", function() require("core.signature").cycle(1) end, { desc = "Next overload (parameter viewer)" })
map("i", "<A-p>", function() require("core.signature").cycle(-1) end, { desc = "Previous overload (parameter viewer)" })

-- Formatting ----------------------------------------------------------------
-- Which formatter runs is set in lua/user/format.lua. The visual mapping goes
-- through the LSP (external formatters always take the whole buffer).
map("n", "<leader>=", function() require("core.format").format({ async = true }) end, { desc = "Format buffer" })
map("x", "<leader>=", function()
  local a, b = vim.fn.line("v"), vim.fn.line(".")
  vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "nx", false)
  require("core.format").format_range(math.min(a, b), math.max(a, b))
end, { desc = "Format selection (LSP)" })
map("n", "<leader>uf", function() require("core.format").toggle() end, { desc = "Toggle format on save (global)" })
map("n", "<leader>uF", function() require("core.format").toggle(0) end, { desc = "Toggle format on save (buffer)" })

-- Git (lua/core/git.lua) ----------------------------------------------------
-- Toggles live under <leader>u, next to format-on-save and spell check.
map("n", "<leader>ub", function() require("core.git").blame_toggle() end, { desc = "Toggle git blame (global)" })
map("n", "<leader>uB", function() require("core.git").blame_toggle(0) end, { desc = "Toggle git blame (buffer)" })
map("n", "<leader>ug", "<cmd>GitSignsToggle<CR>", { desc = "Toggle git signs" })
-- Git hunks: the added / changed / deleted regions shown in the sign column.
map("n", "]h", function() require("core.gitsigns").next_hunk() end, { desc = "Next git hunk" })
map("n", "[h", function() require("core.gitsigns").prev_hunk() end, { desc = "Previous git hunk" })
map("n", "<leader>gp", function() require("core.gitsigns").preview_hunk() end, { desc = "Preview git hunk" })

-- Windows -------------------------------------------------------------------
map("n", "<leader>w", "<C-w>", { remap = false, desc = "Window commands" })

local arrows = { h = "Left", j = "Down", k = "Up", l = "Right" }

for dir, arrow in pairs(arrows) do
  -- Focus: Ctrl+hjkl (normal, terminal) and Ctrl+arrows (also insert).
  local focus = "<C-\\><C-n><C-w>" .. dir
  map({ "n", "t" }, "<C-S-" .. dir .. ">", focus, { desc = "Focus window " .. dir })
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
map({ "n", "i", "t" }, "<A-S-h>", "<C-\\><C-n><cmd>tabprevious<CR>", { desc = "Previous tab" })
map({ "n", "i", "t" }, "<A-S-l>", "<C-\\><C-n><cmd>tabnext<CR>", { desc = "Next tab" })
map({ "n", "i", "t" }, "<A-S-Left>", "<C-\\><C-n><cmd>tabprevious<CR>", { desc = "Previous tab" })
map({ "n", "i", "t" }, "<A-S-Right>", "<C-\\><C-n><cmd>tabnext<CR>", { desc = "Next tab" })

map("n", "<leader>tn", "<cmd>tabnew<CR>", { desc = "New tab" })
map("n", "<leader>tc", "<cmd>tabclose<CR>", { desc = "Close tab" })
map("n", "<leader>to", "<cmd>tabonly<CR>", { desc = "Close other tabs" })
map({ "n", "i", "t" }, "<A-t>", "<C-\\><C-n><cmd>tabnew<CR>", { desc = "New tab" })
