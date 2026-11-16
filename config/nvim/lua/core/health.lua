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
  local tc = native.toolchain()
  if tc.make then
    vim.health.ok(tc.make .. " found")
  end
  if tc.cc then
    vim.health.ok(tc.cc .. " found")
  end
  if #tc.missing > 0 then
    vim.health.warn(
      table.concat(tc.missing, " and ") .. " not found; picker will use the Lua fallback",
      vim.split("Install GNU make and a C compiler:\n" .. native.install_hint(true), "\n", { plain = true })
    )
  end
  vim.health.info("sources: " .. native.paths.src)
  vim.health.info("library: " .. native.paths.lib)

  local lib, err = native.load()
  if lib then
    vim.health.ok("native core " .. native.version() .. " loaded")
  else
    vim.health.warn("native core unavailable: " .. tostring(err))
  end

  vim.health.start("core.completion")
  local copt = vim.opt.completeopt:get()
  for _, need in ipairs({ "menuone", "noinsert" }) do
    if vim.tbl_contains(copt, need) then
      vim.health.ok("'completeopt' has " .. need)
    else
      vim.health.error(("'completeopt' lacks '%s'; accepting without inserting needs it (set in lua/user/options.lua)"):format(need))
    end
  end
  if vim.tbl_contains(copt, "popup") then
    vim.health.ok("'completeopt' has popup (documentation window)")
  else
    vim.health.warn("'completeopt' lacks 'popup'; completion documentation will not be shown")
  end
  if vim.tbl_contains(copt, "noselect") then
    vim.health.warn("'completeopt' has noselect; <CR> still accepts the first entry when none is highlighted")
  end
  if vim.snippet and vim.snippet.expand then
    vim.health.ok("vim.snippet available")
  else
    vim.health.error("vim.snippet missing; snippet completions cannot be expanded")
  end
  if vim.api.nvim_complete_set or vim.api.nvim__complete_set then
    vim.health.ok("lazy documentation updates supported")
  else
    vim.health.info("no nvim_complete_set; documentation only shows for items that arrive with it")
  end

  vim.health.start("core.format")
  local format = require("core.format")
  local names = vim.tbl_keys(format.formatters)
  table.sort(names)
  if #names == 0 then
    vim.health.info("no formatters defined (lua/user/format.lua)")
  end
  for _, name in ipairs(names) do
    local cmd = format.formatters[name].cmd
    if vim.fn.executable(cmd) == 1 then
      vim.health.ok(("%s: '%s' found"):format(name, cmd))
    else
      vim.health.info(("%s skipped: '%s' not found in PATH"):format(name, cmd))
    end
  end
  vim.health.info(("format on save: %s"):format(format.enabled() and "on" or "off"))

  vim.health.start("core.treesitter")
  local ts = require("core.treesitter")
  for _, lang in ipairs(require("core.config").get().treesitter.languages) do
    local parser, query = ts.available(lang)
    if parser and query then
      vim.health.ok(("%s: parser and highlights query found"):format(lang))
    elseif parser then
      vim.health.warn(("%s: parser found but no queries/%s/highlights.scm; regex syntax stays on"):format(lang, lang))
    else
      vim.health.info(("%s: no parser on 'runtimepath' (parser/%s.so); regex syntax is used"):format(lang, lang))
    end
  end
  vim.health.info(("put extra parsers in %s/site/parser and queries in %s/site/queries/<lang>"):format(vim.fn.stdpath("data"), vim.fn.stdpath("data")))

  vim.health.start("core.git")
  if vim.fn.executable("git") == 1 then
    vim.health.ok("git found")
  else
    vim.health.warn("git not found; the statusline git section and blame are off")
  end

  vim.health.start("core.projects")
  vim.health.info("file: " .. require("core.config").get().projects.file)
  vim.health.info(("%d saved project(s)"):format(#require("core.projects").list()))

  vim.health.start("core.typst_preview")
  if vim.fn.executable("tinymist") == 1 then
    vim.health.ok("tinymist found")
  else
    vim.health.info("tinymist not found in PATH; the typst preview is unavailable")
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
