local map = vim.keymap.set

local dirs_file = vim.fn.stdpath("data") .. "/cwd_sessions.lua"
local scope_cmds = { window = "lcd", tab = "tcd", global = "cd" }

local function read_dirs()
  if vim.fn.filereadable(dirs_file) == 0 then return {} end
  local chunk = loadfile(dirs_file)
  if not chunk then return {} end
  local ok, data = pcall(chunk)
  return (ok and type(data) == "table") and data or {}
end

local function write_dirs(data)
  local names = vim.tbl_keys(data)
  table.sort(names)
  local lines = { "return {" }
  for _, name in ipairs(names) do
    lines[#lines + 1] = string.format("  [%q] = %q,", name, data[name])
  end
  lines[#lines + 1] = "}"
  vim.fn.writefile(lines, dirs_file)
end

local function sorted_names(data)
  local names = vim.tbl_keys(data)
  table.sort(names)
  return names
end

local function save_dir()
  local cwd = vim.fn.getcwd() -- effective dir for the current window
  local name = vim.fn.input("Name: ", vim.fn.fnamemodify(cwd, ":t"))
  if name == "" then return end
  local data = read_dirs()
  data[name] = cwd
  write_dirs(data)
end

local function load_dir(scope)
  local data = read_dirs()
  local names = sorted_names(data)
  if #names == 0 then return vim.notify("No saved directories") end

  vim.ui.select(names, {
    prompt = "Directory (" .. scope .. ")",
    format_item = function(n) return n .. "  " .. data[n] end,
  }, function(name)
    if not name then return end
    local ok, err = pcall(vim.api.nvim_cmd, { cmd = scope_cmds[scope], args = { data[name] } }, {})
    if not ok then vim.notify(tostring(err), vim.log.levels.ERROR) end
  end)
end

local function delete_dir()
  local data = read_dirs()
  local names = sorted_names(data)
  if #names == 0 then return vim.notify("No saved directories") end

  vim.ui.select(names, {
    prompt = "Delete",
    format_item = function(n) return n .. "  " .. data[n] end,
  }, function(name)
    if not name then return end
    data[name] = nil
    write_dirs(data)
  end)
end

map("n", "<leader>qs", save_dir,   { desc = "Save cwd" })
map("n", "<leader>qd", delete_dir, { desc = "Delete saved cwd" })
map("n", "<leader>qg", function() load_dir("global") end, { desc = "Load cwd (global)" })
map("n", "<leader>qt", function() load_dir("tab") end,    { desc = "Load cwd (tab)" })
map("n", "<leader>qw", function() load_dir("window") end, { desc = "Load cwd (window)" })

return {
  save = save_dir,
  load = load_dir,
  delete = delete_dir,
}
