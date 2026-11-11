vim.pack.add { "https://github.com/stevearc/conform.nvim" }

local by_ft = {
  typst = "typstyle",
}

-- Only register formatters that are actually installed, so a missing binary
-- doesn't produce warnings on every save (same idea as the server list in lsp.lua)
local formatters_by_ft = {}
for ft, exe in pairs(by_ft) do
  if vim.fn.executable(exe) == 1 then
    formatters_by_ft[ft] = { exe }
  end
end

require("conform").setup({
  formatters_by_ft = formatters_by_ft,
  format_on_save = function(bufnr)
    if vim.g.disable_autoformat or vim.b[bufnr].disable_autoformat then
      return
    end
    return { timeout_ms = 2000, lsp_format = "fallback" }
  end,
})
