local config = require("core.config")
local util = require("core.util")

local M = {}

local float = { buf = nil, win = nil }

---@param buf integer
---@return boolean
local function live(buf)
  if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype ~= "terminal" then
    return false
  end
  local job = vim.b[buf].terminal_job_id
  return job ~= nil and vim.fn.jobwait({ job }, 0)[1] == -1
end

--- Values between 0 and 1 are a fraction of `total`; anything else is an
--- absolute number of lines/columns.
---@param value number
---@param total integer
---@return integer
local function size(value, total)
  if value > 0 and value < 1 then
    return math.max(1, math.floor(total * value))
  end
  return math.max(1, math.floor(value))
end

---@param where "bottom"|"right"
function M.open(where)
  local cfg = config.get().terminal
  if where == "right" then
    vim.cmd(("botright vertical %dnew"):format(size(cfg.right_width, vim.o.columns)))
  else
    local rows = vim.o.lines - vim.o.cmdheight
    vim.cmd(("botright %dnew"):format(size(cfg.bottom_height, rows)))
  end
  vim.cmd.terminal()
end

local function float_config()
  local cfg = config.get().terminal.float
  local ui_height = vim.o.lines - vim.o.cmdheight
  local width = math.floor(vim.o.columns * cfg.width)
  local height = math.floor(ui_height * cfg.height)
  return {
    relative = "editor",
    style = "minimal",
    border = cfg.border,
    width = width,
    height = height,
    col = math.floor((vim.o.columns - width) / 2),
    row = math.floor((ui_height - height) / 2),
  }
end

local function float_valid()
  return float.win ~= nil and vim.api.nvim_win_is_valid(float.win)
end

--- Toggle a floating terminal. The shell survives while hidden.
function M.toggle_float()
  if float_valid() then
    vim.api.nvim_win_hide(float.win)
    float.win = nil
    return
  end

  if not (float.buf and vim.api.nvim_buf_is_valid(float.buf)) then
    float.buf = vim.api.nvim_create_buf(false, true)
  end
  float.win = vim.api.nvim_open_win(float.buf, true, float_config())
  vim.wo[float.win].winhighlight = "NormalFloat:Normal"

  if vim.bo[float.buf].buftype ~= "terminal" then
    vim.fn.jobstart(vim.o.shell, { term = true })
  end
  vim.cmd.startinsert()
end

function M.setup()
  local group = util.augroup("terminal")
  local cfg = config.get().terminal

  vim.api.nvim_create_autocmd("TermOpen", {
    group = group,
    callback = function()
      if cfg.hide_numbers then
        vim.opt_local.number = false
        vim.opt_local.relativenumber = false
        vim.opt_local.signcolumn = "no"
      end
    end,
  })

  if cfg.autoinsert then
    vim.api.nvim_create_autocmd({ "TermOpen", "BufEnter", "WinEnter" }, {
      group = group,
      pattern = "term://*",
      callback = function(ev)
        if live(ev.buf) then
          vim.cmd.startinsert()
        end
      end,
    })
  end

  vim.api.nvim_create_autocmd("TermClose", {
    group = group,
    callback = function(ev)
      local status = vim.v.event.status
      if cfg.close_on_exit and status == 0 then
        vim.schedule(function()
          if vim.api.nvim_buf_is_valid(ev.buf) then
            vim.api.nvim_buf_delete(ev.buf, { force = true })
          end
        end)
      elseif status ~= 0 then
        util.notify(("Terminal exited with status %d"):format(status), vim.log.levels.WARN)
      end
    end,
  })

  vim.api.nvim_create_autocmd("VimResized", {
    group = group,
    callback = function()
      if float_valid() then
        vim.api.nvim_win_set_config(float.win, float_config())
      end
    end,
  })

  vim.api.nvim_create_user_command("Term", function(o)
    if o.args == "float" then
      M.toggle_float()
    else
      M.open(o.args == "right" and "right" or "bottom")
    end
  end, {
    nargs = "?",
    complete = function()
      return { "bottom", "right", "float" }
    end,
    desc = "Open a terminal (bottom|right|float)",
  })
end

return M
