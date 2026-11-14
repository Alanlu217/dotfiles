-- Which formatter runs for which filetype (mechanism: lua/core/format.lua).
-- Formatters that are not installed are skipped silently (:FormatInfo, :checkhealth core).
-- A filetype with no formatter available falls back to the LSP (config.format.lsp_fallback).
local format = require("core.format")

format.setup_formatters({
  stylua = {
    cmd = "stylua",
    args = { "--search-parent-directories", "--stdin-filepath", "$FILENAME", "-" },
  },
  ["clang-format"] = {
    cmd = "clang-format",
    args = { "--assume-filename=$FILENAME" },
  },
  rustfmt = {
    cmd = "rustfmt",
    -- Read from stdin, rustfmt cannot see Cargo.toml: set the edition yourself.
    args = { "--edition", "2021" },
  },
  typstyle = {
    cmd = "typstyle",
  },
})

format.by_ft({
  lua = { "stylua" },
  c = { "clang-format" },
  cpp = { "clang-format" },
  rust = { "rustfmt" },
  typst = { "typstyle" },
})
