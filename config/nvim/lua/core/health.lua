-- :checkhealth core
local M = {}

function M.check()
  local native = require("core.native")
  vim.health.start("core")

  if vim.fn.has("nvim-0.11") == 1 then
    vim.health.ok("Neovim >= 0.11")
  else
    vim.health.error("Neovim >= 0.11 required")
  end

  vim.health.start("core.native")
  for _, exe in ipairs({ "make", "cc" }) do
    if vim.fn.executable(exe) == 1 then
      vim.health.ok(exe .. " found")
    else
      vim.health.warn(exe .. " not found; picker will use the Lua fallback")
    end
  end
  vim.health.info("sources: " .. native.paths.src)
  vim.health.info("library: " .. native.paths.lib)

  local lib, err = native.load()
  if lib then
    vim.health.ok("native core " .. native.version() .. " loaded")
  else
    vim.health.warn("native core unavailable: " .. tostring(err))
  end

  vim.health.start("core.lsp")
  local lsp = require("core.lsp")
  if #lsp.enabled == 0 then
    vim.health.info("no language servers enabled")
  end
  for _, name in ipairs(lsp.enabled) do
    vim.health.ok(name .. " enabled")
  end
  for name, exe in pairs(lsp.missing) do
    vim.health.info(("%s skipped: '%s' not found in PATH"):format(name, exe))
  end
end

return M
