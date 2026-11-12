local ffi = require("ffi")
local M = {}

local config_path = vim.fn.stdpath("config")
local native_dir = config_path .. "/native"
local bin_dir = native_dir .. "/bin"
local ext = (jit.os == "OSX") and "dylib" or "so"
local lib_path = bin_dir .. "/core." .. ext
local ffi_header_path = bin_dir .. "/common_ffi.h"

-- Shared build function
local function build_native()
  vim.notify("Building native C library and FFI definitions...", vim.log.levels.INFO)

  -- Use vim.system to run make cleanly without polluting the terminal UI
  local clean_res = vim.system({ "make", "-C", native_dir, "clean" }, { text = true }):wait()
  local build_res = vim.system({ "make", "-C", native_dir }, { text = true }):wait()

  if build_res.code ~= 0 then
    vim.notify("Failed to compile native C library!\n" .. (build_res.stderr or ""), vim.log.levels.ERROR)
    return false
  end
  return true
end

-- autocompile if libs do not exist
if vim.fn.filereadable(lib_path) == 0 or vim.fn.filereadable(ffi_header_path) == 0 then
  if not build_native() then return M end
end

-- load the processed header
if vim.fn.filereadable(ffi_header_path) == 1 then
  local ffi_code = table.concat(vim.fn.readfile(ffi_header_path), "\n")
  pcall(ffi.cdef, ffi_code)
else
  vim.notify("common_ffi.h not found after build!", vim.log.levels.ERROR)
  return M
end

-- load the ffi library
local ok, C = pcall(ffi.load, lib_path)
if not ok then
  vim.notify("Failed to load native library: " .. tostring(C), vim.log.levels.ERROR)
  return M
end

M.C = C

-- expose functions via lua metatable on this module
setmetatable(M, {
  __index = function(_, key)
    return C[key]
  end,
})

-- 5. User-Defined Command: :NativeRebuild
vim.api.nvim_create_user_command("NativeRebuild", function()
  if build_native() then
    vim.notify("Native modules rebuilt successfully! Restart Neovim or restart session to load updates.", vim.log.levels.INFO)
  end
end, { desc = "Clean and recompile native C library and FFI bindings" })

return M
