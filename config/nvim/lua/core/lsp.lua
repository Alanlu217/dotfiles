-- Thin layer over Neovim's built-in LSP client (vim.lsp.config / vim.lsp.enable).
-- Mechanism only: which servers to run and which keys to bind live in lua/user/lsp.lua.
--
-- Neovim >= 0.11 already binds: K (hover), grn (rename), gra (code action),
-- grr (references), gri (implementation), gO (symbols), [d / ]d (diagnostics),
-- and <C-s> in insert mode (signature help).
local config = require("core.config")
local util = require("core.util")

local M = {}

---@type string[] servers that were enabled
M.enabled = {}
---@type table<string, string> servers skipped because their binary is missing (name -> executable)
M.missing = {}

local attach_handlers = {} ---@type (fun(client: vim.lsp.Client, buf: integer))[]

--- Register server configs and enable the ones whose binary is installed.
--- A server whose executable is not on PATH is skipped silently (see :LspInfo).
---@param servers table<string, vim.lsp.Config>
function M.enable(servers)
  for name, cfg in pairs(servers) do
    vim.lsp.config(name, cfg)

    local ok, resolved = pcall(function()
      return vim.lsp.config[name]
    end)
    local cmd = ok and resolved and resolved.cmd or cfg.cmd
    local exe = type(cmd) == "table" and cmd[1] or nil

    if exe and vim.fn.executable(exe) == 0 then
      M.missing[name] = exe
    else
      vim.lsp.enable(name)
      M.enabled[#M.enabled + 1] = name
    end
  end
end

--- Run `fn(client, buf)` whenever a client attaches to a buffer.
---@param fn fun(client: vim.lsp.Client, buf: integer)
function M.on_attach(fn)
  attach_handlers[#attach_handlers + 1] = fn
end

--- Format the buffer without blocking the editor.
---@param opts? table passed to vim.lsp.buf.format
function M.format(opts)
  vim.lsp.buf.format(vim.tbl_extend("force", { async = true }, opts or {}))
end

function M.setup()
  vim.diagnostic.config(config.get().lsp.diagnostics)

  vim.api.nvim_create_autocmd("LspAttach", {
    group = util.augroup("lsp"),
    callback = function(ev)
      local client = vim.lsp.get_client_by_id(ev.data.client_id)
      if not client then
        return
      end
      for _, fn in ipairs(attach_handlers) do
        fn(client, ev.buf)
      end
    end,
  })

  vim.api.nvim_create_user_command("LspInfo", function()
    local lines = {}
    for _, client in ipairs(vim.lsp.get_clients({ bufnr = 0 })) do
      lines[#lines + 1] = ("%s  root: %s"):format(client.name, client.root_dir or "-")
    end
    if #lines == 0 then
      lines[1] = "No LSP clients attached to this buffer"
    end
    for name, exe in pairs(M.missing) do
      lines[#lines + 1] = ("%s: '%s' not found in PATH"):format(name, exe)
    end
    util.notify(table.concat(lines, "\n"))
  end, { desc = "Show LSP clients for this buffer and missing servers" })

  vim.api.nvim_create_user_command("LspRestart", function()
    local names = {}
    for _, client in ipairs(vim.lsp.get_clients({ bufnr = 0 })) do
      names[#names + 1] = client.name
    end
    for _, name in ipairs(names) do
      vim.lsp.enable(name, false)
    end
    vim.defer_fn(function()
      for _, name in ipairs(names) do
        vim.lsp.enable(name)
      end
    end, 300)
  end, { desc = "Restart the LSP clients attached to this buffer" })

  vim.api.nvim_create_user_command("LspLog", function()
    vim.cmd.edit(vim.lsp.log.get_filename())
  end, { desc = "Open the LSP log" })
end

return M
