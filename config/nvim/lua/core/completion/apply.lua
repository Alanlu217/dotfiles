-- Accepting an item: turns a menu entry into a buffer edit.
--
-- Runs after the native menu has been closed (see session.commit), so the
-- buffer is exactly as it was when the menu was built and may be edited freely.
--
-- Handled for LSP items: textEdit (TextEdit and InsertReplaceEdit, using the
-- insert range), insertText, snippets (vim.snippet), additionalTextEdits
-- (from the item, from a cached completionItem/resolve, or fetched after the
-- fact) and commands. Path and buffer-word items are plain text replacements.
local M = {}

local ns = vim.api.nvim_create_namespace("core_completion_apply")

--- Byte column of an LSP position's `character` on line `lnum` (0-based).
---@param buf integer
---@param lnum integer
---@param character integer
---@param enc string
---@return integer
local function byte_col(buf, lnum, character, enc)
  local line = vim.api.nvim_buf_get_lines(buf, lnum, lnum + 1, false)[1] or ""
  local ok, idx = pcall(vim.str_byteindex, line, enc or "utf-16", character, false)
  if ok and type(idx) == "number" then
    return idx
  end
  return math.min(character, #line)
end

---@param text string
---@return string[]
local function split_lines(text)
  text = text:gsub("\r\n?", "\n")
  return vim.split(text, "\n", { plain = true })
end

--- Replace [r1,c1 .. r2,c2) with `text` and put the cursor after it.
---@param buf integer
---@param win integer
local function put_text(buf, win, r1, c1, r2, c2, text)
  local lines = split_lines(text)
  vim.api.nvim_buf_set_text(buf, r1, c1, r2, c2, lines)
  local row = r1 + #lines - 1
  local col = (#lines == 1) and (c1 + #lines[1]) or #lines[#lines]
  vim.api.nvim_win_set_cursor(win, { row + 1, col })
end

--- Replace the range with a snippet and start the snippet session.
---@param buf integer
---@param win integer
local function put_snippet(buf, win, r1, c1, r2, c2, text)
  vim.api.nvim_buf_set_text(buf, r1, c1, r2, c2, { "" })
  vim.api.nvim_win_set_cursor(win, { r1 + 1, c1 })
  local ok = pcall(vim.snippet.expand, text)
  if not ok then
    -- Malformed snippet: insert it as plain text rather than lose the item.
    local plain = text
    if vim.lsp.util.parse_snippet then
      local parsed_ok, parsed = pcall(vim.lsp.util.parse_snippet, text)
      if parsed_ok and type(parsed) == "string" then
        plain = parsed
      end
    end
    put_text(buf, win, r1, c1, r1, c1, plain)
  end
end

---@param it core.completion.Item
---@param ctx table context the menu was built for
function M.accept(it, ctx)
  local buf, win = ctx.buf, vim.api.nvim_get_current_win()
  local session = require("core.completion.session")

  -- Defaults: replace the word typed so far.
  local sl, sc, el, ec = ctx.lnum, ctx.start_col, ctx.lnum, ctx.col
  local text, snippet, additional
  local lsp = it.lsp

  if lsp then
    local edit = lsp.textEdit
    local range = edit and (edit.range or edit.insert)
    if range then
      sl = range.start.line
      sc = byte_col(buf, sl, range.start.character, it.enc)
      el = range["end"].line
      ec = byte_col(buf, el, range["end"].character, it.enc)
      -- The server answered for a shorter word; swallow what was typed since.
      if el == ctx.lnum and ec < ctx.col then
        ec = ctx.col
      end
      text = edit.newText
    else
      text = lsp.insertText or lsp.label
    end
    snippet = lsp.insertTextFormat == 2
    additional = lsp.additionalTextEdits or (type(it.resolved) == "table" and it.resolved.additionalTextEdits) or nil
    if additional and #additional == 0 then
      additional = nil
    end
  else
    text = it.insert or it.label
  end

  -- Additional edits (typically an import above) move lines around; extmarks
  -- keep the main range valid while they are applied.
  local r1, c1, r2, c2 = sl, sc, el, ec
  if additional then
    local m1 = vim.api.nvim_buf_set_extmark(buf, ns, sl, sc, { right_gravity = true, strict = false })
    local m2 = vim.api.nvim_buf_set_extmark(buf, ns, el, ec, { right_gravity = false, strict = false })
    local ok, err = pcall(vim.lsp.util.apply_text_edits, additional, buf, it.enc or "utf-16")
    local p1 = vim.api.nvim_buf_get_extmark_by_id(buf, ns, m1, {})
    local p2 = vim.api.nvim_buf_get_extmark_by_id(buf, ns, m2, {})
    vim.api.nvim_buf_del_extmark(buf, ns, m1)
    vim.api.nvim_buf_del_extmark(buf, ns, m2)
    if not ok then
      vim.notify("completion: additionalTextEdits failed: " .. tostring(err), vim.log.levels.WARN)
    elseif #p1 > 0 and #p2 > 0 then
      r1, c1, r2, c2 = p1[1], p1[2], p2[1], p2[2]
    end
  end

  if snippet then
    put_snippet(buf, win, r1, c1, r2, c2, text)
  else
    put_text(buf, win, r1, c1, r2, c2, text)
  end

  local client = it.client_id and vim.lsp.get_client_by_id(it.client_id)
  if client and lsp then
    if lsp.command then
      pcall(client.exec_cmd, client, lsp.command, { bufnr = buf })
    end
    -- Nothing yet (neither on the item nor from a resolve done while the item
    -- was highlighted): ask now, apply when it arrives.
    local provider = client.server_capabilities and client.server_capabilities.completionProvider
    if not additional and type(it.resolved) ~= "table" and provider and provider.resolveProvider then
      client:request("completionItem/resolve", lsp, function(err, res)
        if err or not res or not res.additionalTextEdits or #res.additionalTextEdits == 0 then
          return
        end
        if not vim.api.nvim_buf_is_valid(buf) then
          return
        end
        pcall(vim.lsp.util.apply_text_edits, res.additionalTextEdits, buf, it.enc or "utf-16")
        session.suppress(buf)
      end, buf)
    end
  end

  session.suppress(buf)
end

return M
