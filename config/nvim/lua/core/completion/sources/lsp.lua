-- LSP source: textDocument/completion from every attached client that offers it.
--
-- Items are normalised into the shape every source produces (see session.lua);
-- the raw LSP item is kept in `lsp` so apply.lua can honour textEdit,
-- additionalTextEdits, snippets and commands.
local M = {}

M.name = "lsp"

-- Indexed by lsp.CompletionItemKind. Short ASCII, no icons.
local KIND = {
  "Txt", "Fn", "Fn", "Ctor", "Fld", "Var", "Cls", "Ifc", "Mod", "Prop", "Unit", "Val", "Enum",
  "Kw", "Snip", "Clr", "File", "Ref", "Dir", "Mem", "Const", "Str", "Evt", "Op", "Type",
}

--- Characters (declared by the attached servers) that should open the menu.
---@param buf integer
---@return table<string, true>
function M.trigger_chars(buf)
  local set = {}
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = buf, method = "textDocument/completion" })) do
    local provider = client.server_capabilities and client.server_capabilities.completionProvider
    for _, ch in ipairs(provider and provider.triggerCharacters or {}) do
      set[ch] = true
    end
  end
  return set
end

--- Documentation text for the info popup: detail first, then the docs.
---@param item table lsp.CompletionItem
---@return string?
function M.doc_text(item)
  local parts = {}
  if type(item.detail) == "string" and item.detail ~= "" then
    parts[#parts + 1] = item.detail
  end
  local doc = item.documentation
  if type(doc) == "table" then
    doc = doc.value
  end
  if type(doc) == "string" and doc ~= "" then
    parts[#parts + 1] = doc
  end
  if #parts == 0 then
    return nil
  end
  local text = table.concat(parts, "\n\n")
  -- The popup is plain text: drop markdown code fences, keep their content.
  text = text:gsub("```[%w_+%-]*[ \t]*\r?\n", ""):gsub("\r?\n?```", "")
  return text
end

---@param item table lsp.CompletionItem
---@param defaults? table CompletionList.itemDefaults
---@param client vim.lsp.Client
---@return table
local function convert(item, defaults, client)
  if defaults then
    item.insertTextFormat = item.insertTextFormat or defaults.insertTextFormat
    item.insertTextMode = item.insertTextMode or defaults.insertTextMode
    item.data = item.data or defaults.data
    local range = defaults.editRange
    if range and not item.textEdit then
      local text = item.textEditText or item.insertText or item.label
      if range.start then
        item.textEdit = { newText = text, range = range }
      elseif range.insert then
        item.textEdit = { newText = text, insert = range.insert, replace = range.replace }
      end
    end
  end

  local label = tostring(item.label):gsub("[\r\n]+", " ")
  local details = item.labelDetails
  local abbr = label .. ((details and details.detail) or "")

  return {
    source = "lsp",
    label = label,
    abbr = abbr,
    filter = item.filterText or label,
    sort = item.sortText or label,
    kind = KIND[item.kind],
    menu = client.name,
    doc = M.doc_text(item),
    lsp = item,
    client_id = client.id,
    enc = client.offset_encoding,
  }
end

---@param client vim.lsp.Client
---@param ctx table
---@return table
local function request_context(client, ctx)
  local provider = client.server_capabilities and client.server_capabilities.completionProvider
  local last = ctx.before:sub(-1)
  if ctx.incomplete then
    return { triggerKind = 3 } -- TriggerForIncompleteCompletions
  end
  if last ~= "" and provider and vim.tbl_contains(provider.triggerCharacters or {}, last) then
    return { triggerKind = 2, triggerCharacter = last }
  end
  return { triggerKind = 1 }
end

--- Ask every client. `cb` is called once, when all have answered.
---@param ctx table
---@param cb fun(items: table[], incomplete: boolean)
---@return fun() cancel
function M.fetch(ctx, cb)
  local clients = vim.lsp.get_clients({ bufnr = ctx.buf, method = "textDocument/completion" })
  if #clients == 0 then
    cb({}, false)
    return function() end
  end

  local items, incomplete, cancelled = {}, false, false
  local remaining = #clients
  local requests = {} ---@type { client: vim.lsp.Client, id: integer }[]

  local function done_one()
    remaining = remaining - 1
    if remaining == 0 and not cancelled then
      cb(items, incomplete)
    end
  end

  for _, client in ipairs(clients) do
    local params = vim.lsp.util.make_position_params(ctx.win, client.offset_encoding)
    params.context = request_context(client, ctx)

    local ok, id = client:request("textDocument/completion", params, function(err, result)
      if cancelled then
        return
      end
      if not err and result then
        local list, defaults = result, nil
        if not vim.islist(result) then
          list, defaults = result.items or {}, result.itemDefaults
          incomplete = incomplete or result.isIncomplete == true
        end
        for _, item in ipairs(list) do
          items[#items + 1] = convert(item, defaults, client)
        end
      end
      done_one()
    end, ctx.buf)

    if ok and id then
      requests[#requests + 1] = { client = client, id = id }
    else
      done_one()
    end
  end

  return function()
    cancelled = true
    for _, req in ipairs(requests) do
      pcall(req.client.cancel_request, req.client, req.id)
    end
  end
end

return M
