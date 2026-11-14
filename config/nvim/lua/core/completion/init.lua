-- Insert-mode completion: LSP + path + buffer words, merged and fuzzy-ranked,
-- shown in Neovim's native popup menu.
--
--   :Completion [on|off|toggle]      runtime switch (also vim.b.completion = false per buffer)
--
--   require("core.completion").trigger()   open the menu now
--   require("core.completion").hide()      close it
--   require("core.completion").visible()
--
-- The key functions below return keys and are meant for { expr = true } insert
-- mappings (see lua/user/keymaps.lua); each falls back to the key's normal
-- behaviour when there is nothing for it to do:
--   enter()    accept the selected item | <CR> (newline)
--   confirm()  accept the selected item | <C-y>
--   tab()      next menu entry | next snippet placeholder | <Tab>
--   s_tab()    previous menu entry | previous snippet placeholder | <S-Tab>
--   up()/down() close the menu and move the cursor | plain <Up>/<Down>
--   cancel()   close the menu (or cancel a pending request) | <C-e>
-- Moving through entries never edits the buffer; only accepting does.
--
-- Companion: lua/core/signature.lua, the parameter viewer (signature help). It
-- keeps clear of this menu on its own.
--
-- Mechanism only; no options and no keymaps are defined here.
local util = require("core.util")
local session = require("core.completion.session")

local M = {}

local COMMIT = "<C-e><Cmd>lua require('core.completion').commit()<CR>"

--- Keys that accept the selected item, or nil if there is none. The buffer must
--- not change inside an <expr> mapping, so the edit is staged now and applied
--- by commit() once <C-e> has closed the native menu.
---@return string?
local function accept_keys()
  if session.stage_accept() then
    return COMMIT
  end
  return nil
end

function M.commit()
  session.commit()
end

---@return string
function M.tab()
  if session.visible() then
    return "<C-n>" -- native: highlight the next entry; the buffer text is unchanged
  end
  if vim.snippet.active({ direction = 1 }) then
    return "<Cmd>lua vim.snippet.jump(1)<CR>"
  end
  return "<Tab>"
end

---@return string
function M.s_tab()
  if session.visible() then
    return "<C-p>"
  end
  if vim.snippet.active({ direction = -1 }) then
    return "<Cmd>lua vim.snippet.jump(-1)<CR>"
  end
  return "<S-Tab>"
end

---@return string
function M.confirm()
  return accept_keys() or "<C-y>"
end

---@return string
function M.cancel()
  local ours = session.visible() or session.busy()
  session.reset(false)
  if vim.fn.pumvisible() == 1 then
    return "<C-e>" -- native: close the menu, keep what was typed
  end
  if ours then
    return "" -- a request was pending; cancelling it is all <C-e> did
  end
  return "<C-e>"
end

---@return string
function M.enter()
  return accept_keys() or "<CR>"
end

--- Arrow keys are not completion keys: natively they would move the menu
--- highlight, so with our menu open, close it and move the cursor instead.
---@param key string
---@return string
local function arrow(key)
  if session.visible() then
    session.reset(false)
    return "<C-e>" .. key
  end
  return key
end

---@return string
function M.up()
  return arrow("<Up>")
end

---@return string
function M.down()
  return arrow("<Down>")
end

--- Open the menu now, even with nothing typed.
function M.trigger()
  session.manual()
end

function M.hide()
  session.reset(true)
end

---@return boolean
function M.visible()
  return session.visible()
end

--- Run an autocmd handler; an error resets the session and is reported once,
--- instead of repeating on every keystroke.
---@param fn fun(...)
local function guarded(fn)
  local reported = false
  return function(...)
    local ok, err = pcall(fn, ...)
    if not ok then
      pcall(session.reset, false)
      if not reported then
        reported = true
        vim.schedule(function()
          util.notify("completion error:\n" .. tostring(err), vim.log.levels.ERROR)
        end)
      end
    end
  end
end

function M.setup()
  local group = util.augroup("completion")
  local function on(events, fn)
    vim.api.nvim_create_autocmd(events, { group = group, callback = guarded(fn) })
  end

  on({ "TextChangedI", "TextChangedP" }, session.on_change)
  on("CursorMovedI", session.on_cursor)
  on("CompleteChanged", session.on_select)
  on({ "InsertLeave", "BufLeave" }, function()
    session.reset(false)
  end)
  on("BufWipeout", function(ev)
    require("core.completion.sources.buffer").forget(ev.buf)
  end)

  vim.api.nvim_create_user_command("Completion", function(o)
    local arg = o.args
    if arg == "on" then
      session.enabled = true
    elseif arg == "off" then
      session.enabled = false
    elseif arg == "" or arg == "toggle" then
      session.enabled = not session.enabled
    else
      util.notify("Completion: expected on, off or toggle", vim.log.levels.ERROR)
      return
    end
    if not session.enabled then
      session.reset(true)
    end
    util.notify("Completion " .. (session.enabled and "on" or "off"))
  end, {
    nargs = "?",
    complete = function()
      return { "on", "off", "toggle" }
    end,
    desc = "Toggle insert-mode completion (on|off|toggle)",
  })
end

return M
