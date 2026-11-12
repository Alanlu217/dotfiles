-- Leader
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Test
local native = require("core.ffi")
local ffi = require("ffi")

local version_ptr = native.native_core_version()
if version_ptr ~= nil then
  vim.print("Native Core Version: " .. ffi.string(version_ptr))
end

-- Module imports

local modules = {
  -- core
  "core.ffi",

  "options",
  "keymap",
  "terminal",
}

local failed = {}

for _, mod in ipairs(modules) do
  local ok, err = pcall(require, mod)
  if not ok then
    table.insert(failed, { mod = mod, err = err })
  end
end

if #failed > 0 then
  vim.schedule(function()
    for _, f in ipairs(failed) do
      vim.notify(
        ("Failed to load '%s':\n%s"):format(f.mod, f.err),
        vim.log.levels.ERROR
      )
    end
  end)
end
