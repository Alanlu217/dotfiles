-- Buffer-word source: identifiers from the loaded buffers.
--
-- Word counts are cached per buffer and rescanned only when its changedtick
-- moves, i.e. at most once per fetch (a fetch happens at the start of a word,
-- not on every keystroke).
local config = require("core.config")
local native = require("core.native")

local M = {}

M.name = "buffer"

local MIN_LENGTH = 3

---@type table<integer, { tick: integer, counts: table<string, integer> }>
local cache = {}

---@param buf integer
---@param cfg table
---@return table<string, integer>?
local function counts_for(buf, cfg)
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  local hit = cache[buf]
  if hit and hit.tick == tick then
    return hit.counts
  end

  local size = vim.api.nvim_buf_get_offset(buf, vim.api.nvim_buf_line_count(buf))
  if size > cfg.max_bytes then
    cache[buf] = { tick = tick, counts = {} }
    return cache[buf].counts
  end

  local counts, n = {}, 0
  local lib = native.loaded()
  if lib then
    -- One C pass over the text instead of a gmatch per line; only distinct words
    -- come back into Lua.
    local ffi = require("ffi")
    local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
    local w = lib.nv_words_collect(text, #text, MIN_LENGTH, cfg.max_words)
    if w ~= nil then
      for i = 0, tonumber(lib.nv_words_count(w)) - 1 do
        counts[ffi.string(lib.nv_words_get(w, i))] = tonumber(lib.nv_words_occurrences(w, i))
      end
      lib.nv_words_free(w)
      cache[buf] = { tick = tick, counts = counts }
      return counts
    end
  end
  for _, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    for word in line:gmatch("[%w_\128-\255]+") do
      if #word >= MIN_LENGTH and not word:find("^%d") then
        local c = counts[word]
        if c then
          counts[word] = c + 1
        else
          counts[word] = 1
          n = n + 1
          if n >= cfg.max_words then
            goto done
          end
        end
      end
    end
  end
  ::done::
  cache[buf] = { tick = tick, counts = counts }
  return counts
end

---@param ctx table
---@param cb fun(items: table[], incomplete: boolean)
---@return fun() cancel
function M.fetch(ctx, cb)
  local cfg = config.get().completion.buffer

  -- The word being typed is itself in the buffer; never offer it to itself.
  local after = ctx.line:sub(ctx.col + 1):match("^[%w_\128-\255]*")
  local cword = ctx.prefix .. after

  local bufs = { ctx.buf }
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if b ~= ctx.buf and vim.api.nvim_buf_is_loaded(b) and vim.bo[b].buftype == "" then
      bufs[#bufs + 1] = b
    end
  end

  local total, items = {}, {}
  for _, b in ipairs(bufs) do
    for word, n in pairs(counts_for(b, cfg)) do
      if b == ctx.buf and word == cword then
        n = n - 1
      end
      if n > 0 then
        total[word] = true
      end
    end
  end
  for word in pairs(total) do
    items[#items + 1] = { source = "buffer", label = word, filter = word, sort = word, menu = "buf", insert = word }
  end

  cb(items, false)
  return function() end
end

--- Drop cached counts of wiped buffers.
function M.forget(buf)
  cache[buf] = nil
end

return M
