-- Which language servers to run, and what to bind when one attaches.
-- Servers whose executable is not installed are skipped silently (:LspInfo).
local lsp = require("core.lsp")

lsp.enable({
  lua_ls = {
    cmd = { "lua-language-server" },
    filetypes = { "lua" },
    root_markers = { ".luarc.json", ".luarc.jsonc", ".stylua.toml", "stylua.toml", ".git" },
    settings = {
      Lua = {
        runtime = { version = "LuaJIT" },
        diagnostics = { globals = { "vim" } },
        workspace = { checkThirdParty = false, library = { vim.env.VIMRUNTIME, "${3rd}/luv/library" } },
        telemetry = { enable = false },
      },
    },
  },

  clangd = {
    cmd = { "clangd", "--background-index" },
    filetypes = { "c", "cpp" },
    root_markers = { "compile_commands.json", ".clangd", "Makefile", ".git" },
  },

  rust_analyzer = {
    cmd = { "rust-analyzer" },
    filetypes = { "rust" },
    root_markers = { "Cargo.toml", "rust-project.json" },
  },

  tinymist = {
    cmd = { "tinymist" },
    filetypes = { "typst" },
    root_markers = { "typst.toml", ".git" },
  },
})

lsp.on_attach(function(client, buf)
  local function map(lhs, rhs, desc)
    vim.keymap.set("n", lhs, rhs, { buffer = buf, desc = desc })
  end

  map("gd", vim.lsp.buf.definition, "Go to definition")
  map("gD", vim.lsp.buf.declaration, "Go to declaration")
  map("<leader>lf", function() lsp.format() end, "Format buffer")
  map("<leader>ld", vim.diagnostic.open_float, "Line diagnostics")

  if client:supports_method("textDocument/inlayHint", buf) then
    map("<leader>lh", function()
      local on = vim.lsp.inlay_hint.is_enabled({ bufnr = buf })
      vim.lsp.inlay_hint.enable(not on, { bufnr = buf })
    end, "Toggle inlay hints")
  end
end)
