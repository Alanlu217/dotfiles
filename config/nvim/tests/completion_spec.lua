-- Headless tests for core.completion and core.signature (the parameter viewer),
-- against a fake in-process LSP server.
--
--   cd ~/.config/nvim && nvim --headless -u NONE -c "luafile tests/completion_spec.lua"
--
-- Exit code 0 = all passed. Results go to stderr. It drives real insert mode
-- through typeahead, so it needs the event loop (hence -c, not -l).
--
-- What this does NOT cover: how the menu looks or feels (flicker, popup
-- placement) in a real terminal. Try that by hand.

local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)

-- Keep the native C library out of it: the matcher falls back to matchfuzzy().
package.loaded["user.config"] = { native = { auto_build = false } }

vim.o.completeopt = "menu,menuone,noinsert,popup"
vim.opt.shortmess:append("c")
vim.o.swapfile = false

local failures = {}
local function check(cond, msg)
  io.stderr:write((cond and "ok:   " or "FAIL: ") .. msg .. "\n")
  if not cond then
    failures[#failures + 1] = msg
  end
end

local function keys(s)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(s, true, false, true), "mt", false)
end

-- Coroutine-driven steps: wait() yields to the event loop so typeahead, timers
-- and LSP replies actually run.
local function wait(ms)
  local co = coroutine.running()
  vim.defer_fn(function()
    local ok, err = coroutine.resume(co)
    if not ok then
      io.stderr:write("ERROR: " .. tostring(err) .. "\n")
      vim.cmd("cquit 2")
    end
  end, ms)
  coroutine.yield()
end

-- Fake language server --------------------------------------------------------

local n_requests = 0

local function edit(params, text)
  local line = vim.api.nvim_buf_get_lines(0, params.position.line, params.position.line + 1, false)[1] or ""
  local prefix = line:sub(1, params.position.character):match("[%w_]*$")
  return {
    range = {
      start = { line = params.position.line, character = params.position.character - #prefix },
      ["end"] = params.position,
    },
    newText = text,
  }, prefix
end

local function completion(params)
  n_requests = n_requests + 1
  local _, prefix = edit(params, "")
  if prefix:sub(1, 3) == "inc" then
    local te = edit(params, "incr")
    return { isIncomplete = true, items = { { label = "incr", kind = 3, textEdit = te } } }
  end
  return {
    { label = "foobar", kind = 3, textEdit = (edit(params, "foobar")) },
    {
      label = "foosnippet",
      kind = 15,
      insertTextFormat = 2,
      textEdit = (edit(params, "foosnippet(${1:a}, ${2:b})")),
    },
    {
      label = "import_me",
      kind = 3,
      textEdit = (edit(params, "import_me")),
      additionalTextEdits = {
        {
          range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 0 } },
          newText = "local x = 1\n",
        },
      },
    },
    { label = "fizz", kind = 6, textEdit = (edit(params, "fizz")) },
  }
end

-- Two overloads of sig(); the active parameter is the number of commas typed
-- since the "(". Nothing once the call is closed.
local function signature_help(params)
  local line = vim.api.nvim_buf_get_lines(0, params.position.line, params.position.line + 1, false)[1] or ""
  local args = line:sub(1, params.position.character):match("sig%(([^)]*)$")
  if not args then
    return nil
  end
  local _, commas = args:gsub(",", "")
  return {
    signatures = {
      { label = "sig(alpha: number, beta: string)", parameters = { { label = "alpha: number" }, { label = "beta: string" } } },
      { label = "sig(gamma)", parameters = { { label = "gamma" } } },
    },
    activeSignature = 0,
    activeParameter = commas,
  }
end

local function server(_dispatchers)
  local closing, next_id = false, 0
  local srv = {}
  function srv.request(method, params, callback)
    next_id = next_id + 1
    vim.schedule(function()
      if method == "initialize" then
        callback(nil, {
          capabilities = {
            completionProvider = { triggerCharacters = { "." } },
            signatureHelpProvider = { triggerCharacters = { "(", "," } },
          },
        })
      elseif method == "textDocument/completion" then
        callback(nil, completion(params))
      elseif method == "textDocument/signatureHelp" then
        callback(nil, signature_help(params))
      else
        callback(nil, nil)
      end
    end)
    return true, next_id
  end
  function srv.notify(method)
    if method == "exit" then
      closing = true
    end
    return true
  end
  function srv.is_closing()
    return closing
  end
  function srv.terminate()
    closing = true
  end
  return srv
end

local function menu_labels()
  local labels = {}
  for _, item in ipairs(vim.fn.complete_info({ "items" }).items or {}) do
    labels[#labels + 1] = item.abbr
  end
  return labels
end

-- Pure parts ------------------------------------------------------------------

do
  local path = require("core.completion.sources.path")
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir .. "/sub", "p")
  vim.fn.writefile({}, dir .. "/sub/file.txt")
  local hit = path.detect({ before = "x = '" .. dir .. "/su", buf = 0 })
  check(hit ~= nil and hit.frag == "su" and hit.dir == vim.fs.normalize(dir), "path: detects an existing directory")
  check(path.detect({ before = "// comment", buf = 0 }) == nil, "path: ignores // comments")
  check(path.detect({ before = "a/b", buf = 0 }) == nil, "path: ignores a/b when a/ does not exist")
end

do
  local sig = require("core.signature")
  -- "f(é, b)": é is one UTF-16 unit but two bytes, so b is at UTF-16 5..6, bytes 6..7.
  local s, e = sig.param_range("f(é, b)", { label = { 5, 6 } })
  check(s == 6 and e == 7, ("signature: UTF-16 offsets map to bytes (got %s,%s)"):format(tostring(s), tostring(e)))
  s, e = sig.param_range("f(a.b, c)", { label = "a.b" })
  check(s == 2 and e == 5, "signature: string label is a plain substring match")
  check(sig.param_range("f(a)", { label = "zzz" }) == nil, "signature: unknown parameter label gives no range")
end

-- End to end ---------------------------------------------------------------------

local co = coroutine.create(function()
  require("core.completion").setup()
  require("core.signature").setup()
  vim.keymap.set("i", "<CR>", function()
    return require("core.completion").enter()
  end, { expr = true })

  vim.cmd("enew")
  vim.bo.buftype = ""
  vim.lsp.start({ name = "fake", cmd = server, root_dir = vim.fn.getcwd() }, { bufnr = 0 })
  wait(300)
  check(#vim.lsp.get_clients({ bufnr = 0 }) == 1, "fake server attached")

  local function reset()
    keys("<Esc>")
    wait(50)
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "" })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
  end

  -- 1. auto-popup + fuzzy filtering + Tab accepts a plain textEdit
  keys("ifoob")
  wait(500)
  local labels = menu_labels()
  check(vim.tbl_contains(labels, "foobar"), "menu offers foobar for 'foob' (got: " .. table.concat(labels, ",") .. ")")
  check(not vim.tbl_contains(labels, "fizz"), "menu filters out fizz")
  keys("<CR>")
  wait(150)
  check(vim.api.nvim_get_current_line() == "foobar", "Enter accepted textEdit: line is '" .. vim.api.nvim_get_current_line() .. "'")
  reset()

  -- 2. snippet item expands and stays active
  keys("ifoos")
  wait(500)
  keys("<CR>")
  wait(150)
  check(vim.api.nvim_get_current_line() == "foosnippet(a, b)", "snippet expanded: '" .. vim.api.nvim_get_current_line() .. "'")
  check(vim.snippet.active(), "snippet session is active")
  vim.snippet.stop()
  reset()

  -- 3. additionalTextEdits at the same position as the word start
  keys("iimp")
  wait(500)
  keys("<CR>")
  wait(150)
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  check(
    lines[1] == "local x = 1" and lines[2] == "import_me",
    "additionalTextEdits applied: " .. vim.inspect(lines)
  )
  reset()

  -- 4. isIncomplete: the next keystroke asks the server again
  keys("iinc")
  wait(500)
  local before = n_requests
  keys("r")
  wait(500)
  check(n_requests == before + 1, ("isIncomplete re-requested (%d -> %d)"):format(before, n_requests))
  check(vim.tbl_contains(menu_labels(), "incr"), "menu still offers incr")
  keys("<Esc>")
  wait(50)

  -- 5. same word, no isIncomplete: further keystrokes do not hit the server
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "" })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  keys("if")
  wait(500)
  before = n_requests
  keys("oo")
  wait(500)
  check(n_requests == before, ("no new request while the word grows (%d -> %d)"):format(before, n_requests))
  keys("<Esc>")
  wait(50)

  -- 6. parameter viewer: opens on "(", follows the commas, cycles overloads, closes with the call
  local viewer = require("core.signature")
  local function float_count()
    local n = 0
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_config(w).relative == "cursor" then
        n = n + 1
      end
    end
    return n
  end
  reset()
  keys("isig(")
  wait(400)
  local cur = viewer.current()
  check(cur ~= nil and cur.count == 2 and cur.index == 1, "viewer opens on '(' with two overloads")
  check(cur ~= nil and cur.param == "alpha: number", "viewer highlights the first parameter (got " .. tostring(cur and cur.param) .. ")")
  check(float_count() == 1, "viewer has one floating window")
  keys("1,")
  wait(400)
  cur = viewer.current()
  check(cur ~= nil and cur.param == "beta: string", "viewer follows the comma (got " .. tostring(cur and cur.param) .. ")")
  viewer.cycle(1)
  cur = viewer.current()
  check(cur ~= nil and cur.index == 2 and cur.label == "sig(gamma)", "cycle shows the second overload")
  check(cur ~= nil and cur.param == nil, "no highlight when the active parameter is out of range")
  viewer.cycle(1)
  cur = viewer.current()
  check(cur ~= nil and cur.index == 1, "cycle wraps around")
  keys(")")
  wait(400)
  check(viewer.current() == nil and float_count() == 0, "viewer closes when the call is closed")
  reset()
  keys("isig(")
  wait(400)
  check(viewer.current() ~= nil, "viewer reopens")
  keys("<Esc>")
  wait(100)
  check(viewer.current() == nil and float_count() == 0, "viewer closes on <Esc>")

  if #failures == 0 then
    io.stderr:write("\nall passed\n")
    vim.cmd("qa!")
  else
    io.stderr:write(("\n%d failed\n"):format(#failures))
    vim.cmd("cquit 1")
  end
end)

vim.defer_fn(function()
  local ok, err = coroutine.resume(co)
  if not ok then
    io.stderr:write("ERROR: " .. tostring(err) .. "\n")
    vim.cmd("cquit 2")
  end
end, 50)

vim.defer_fn(function()
  io.stderr:write("TIMEOUT\n")
  vim.cmd("cquit 3")
end, 30000)
