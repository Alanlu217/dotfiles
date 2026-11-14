-- LSP symbol pickers: symbols of the current file, and workspace-wide symbols.
--
-- Document symbols are fetched once, then fuzzy-filtered locally.
-- Workspace symbols are queried from the server on every keystroke (servers
-- filter and rank them; most return little or nothing for an empty query).
local matcher = require("core.picker.matcher")
local ui = require("core.picker.ui")
local util = require("core.util")

local M = {}

---@class core.picker.Symbol
---@field name string
---@field kind integer
---@field container? string
---@field uri string
---@field range? lsp.Range
---@field enc string offset encoding of the client that returned it

local JUMP_CMDS = { edit = nil, split = "split", vsplit = "vsplit", tabedit = "tab split" }

--- Flatten DocumentSymbol trees, SymbolInformation and WorkspaceSymbol lists.
---@param symbols table[]
---@param uri? string uri of the document (only needed for DocumentSymbol)
---@param enc string
---@param out core.picker.Symbol[]
---@param container? string
local function flatten(symbols, uri, enc, out, container)
  for _, s in ipairs(symbols) do
    if s.location then
      out[#out + 1] = {
        name = s.name,
        kind = s.kind,
        container = s.containerName ~= "" and s.containerName or nil,
        uri = s.location.uri,
        range = s.location.range,
        enc = enc,
      }
    elseif uri then
      out[#out + 1] = {
        name = s.name,
        kind = s.kind,
        container = container,
        uri = uri,
        range = s.selectionRange or s.range,
        enc = enc,
      }
      if s.children then
        flatten(s.children, uri, enc, out, container and (container .. "." .. s.name) or s.name)
      end
    end
  end
end

---@param sym core.picker.Symbol
---@param with_path boolean
---@return string
local function label(sym, with_path)
  local kind = vim.lsp.protocol.SymbolKind[sym.kind] or "Unknown"
  local where = ""
  if with_path then
    where = vim.fn.fnamemodify(vim.uri_to_fname(sym.uri), ":~:.")
  end
  if sym.range then
    where = ("%s:%d"):format(where, sym.range.start.line + 1)
  end
  local text = ("%-11s %s%s  %s"):format(kind, sym.name, sym.container and ("  " .. sym.container) or "", where)
  return (text:gsub("[\r\n]+", " "))
end

---@param sym core.picker.Symbol
---@param action "edit"|"split"|"vsplit"|"tabedit"
local function jump(sym, action)
  vim.cmd("normal! m'") -- keep the old position in the jumplist
  local cmd = JUMP_CMDS[action]
  if cmd then
    vim.cmd(cmd)
  end
  local pos = { line = 0, character = 0 }
  local range = sym.range or { start = pos, ["end"] = pos }
  vim.lsp.util.show_document({ uri = sym.uri, range = range }, sym.enc, { reuse_win = false, focus = true })
end

--- Labels for `syms`, made unique, recorded in `lookup`.
---@param syms core.picker.Symbol[]
---@param with_path boolean
---@param lookup table<string, core.picker.Symbol>
---@param limit? integer
---@return string[]
local function labels_for(syms, with_path, lookup, limit)
  local labels, seen = {}, {}
  for _, sym in ipairs(syms) do
    if limit and #labels >= limit then
      break
    end
    local text = label(sym, with_path)
    seen[text] = (seen[text] or 0) + 1
    if seen[text] > 1 then
      text = ("%s [%d]"):format(text, seen[text])
    end
    labels[#labels + 1] = text
    lookup[text] = sym
  end
  return labels
end

---@param method string
---@return vim.lsp.Client[]
local function clients_for(method)
  return vim.lsp.get_clients({ bufnr = 0, method = method })
end

--- Symbols of the current buffer.
function M.document()
  local buf = vim.api.nvim_get_current_buf()
  if #clients_for("textDocument/documentSymbol") == 0 then
    util.notify("No language server with document symbols for this buffer", vim.log.levels.WARN)
    return
  end

  local params = { textDocument = vim.lsp.util.make_text_document_params(buf) }
  vim.lsp.buf_request_all(buf, "textDocument/documentSymbol", params, function(results)
    local syms = {}
    for id, res in pairs(results) do
      local client = vim.lsp.get_client_by_id(id)
      if client and res.result then
        flatten(res.result, params.textDocument.uri, client.offset_encoding, syms)
      end
    end
    if #syms == 0 then
      util.notify("No symbols found")
      return
    end

    local lookup = {}
    ui.open({
      title = "Symbols",
      matcher = matcher.from_list(labels_for(syms, false, lookup)),
      on_select = function(item, action)
        local sym = lookup[item]
        if sym then
          jump(sym, action)
        end
      end,
    })
  end)
end

--- Matcher that asks the language servers for symbols matching the query.
---@param buf integer
---@param clients vim.lsp.Client[]
---@param lookup table<string, core.picker.Symbol>
---@return core.Matcher
local function workspace_matcher(buf, clients, lookup)
  local last = 0
  local m = { loading = false, truncated = false, disposed = false }
  m.count = function()
    return last
  end
  m.subscribe = function() end
  m.dispose = function()
    m.disposed = true
  end
  m.filter = function(query, limit, cb)
    local pending, syms = #clients, {}
    local function done()
      pending = pending - 1
      if pending > 0 or m.disposed then
        return
      end
      local labels = labels_for(syms, true, lookup, limit)
      last = #labels
      cb(labels)
    end
    for _, client in ipairs(clients) do
      local ok = client:request("workspace/symbol", { query = query }, function(_, result)
        if result then
          flatten(result, nil, client.offset_encoding, syms)
        end
        done()
      end, buf)
      if not ok then
        done()
      end
    end
  end
  return m
end

--- Symbols across the workspace, queried from the language servers.
function M.workspace()
  local clients = clients_for("workspace/symbol")
  if #clients == 0 then
    util.notify("No language server with workspace symbols for this buffer", vim.log.levels.WARN)
    return
  end

  local lookup = {}
  ui.open({
    title = "Workspace symbols",
    matcher = workspace_matcher(vim.api.nvim_get_current_buf(), clients, lookup),
    on_select = function(item, action)
      local sym = lookup[item]
      if sym then
        jump(sym, action)
      end
    end,
  })
end

return M
