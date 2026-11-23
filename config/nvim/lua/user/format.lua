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
  -- Import sorting first (exit 1 only means unfixable violations remain), then format.
  ruff_organize = {
    cmd = "ruff",
    args = { "check", "--select", "I", "--fix", "--quiet", "--stdin-filename", "$FILENAME", "-" },
    exit_codes = { 0, 1 },
  },
  ruff_format = {
    cmd = "ruff",
    args = { "format", "--stdin-filename", "$FILENAME", "-" },
  },
})

format.by_ft({
  lua = { "stylua" },
  c = { "clang-format" },
  cpp = { "clang-format" },
  rust = { "rustfmt" },
  python = { "ruff_organize", "ruff_format" },
  -- julia: no entry, so the LSP (JuliaFormatter via LanguageServer.jl) formats.
})
