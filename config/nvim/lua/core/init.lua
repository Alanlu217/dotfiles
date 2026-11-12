local util = require("core.util")

local M = {}

-- Framework features, each exposing setup() (autocmds + commands, no keymaps).
local features = { "core.native", "core.terminal", "core.picker", "core.lsp" }

function M.start()
  for _, name in ipairs(features) do
    local ok, mod = util.safe_require(name)
    if ok and type(mod.setup) == "function" then
      local setup_ok, err = pcall(mod.setup)
      if not setup_ok then
        vim.schedule(function()
          util.notify(("%s.setup() failed:\n%s"):format(name, err), vim.log.levels.ERROR)
        end)
      end
    end
  end

  vim.api.nvim_create_user_command("ReloadConfig", M.reload, { desc = "Reload this Neovim config" })

  -- Hand over to user space last, so it can rely on everything above.
  util.safe_require("user")
end

--- Drop every module owned by this config and start again. Mappings or options
--- you *removed* from user files persist until restart.
function M.reload()
  for name in pairs(package.loaded) do
    if name == "core" or name == "user" or name:find("^core%.") or name:find("^user%.") then
      package.loaded[name] = nil
    end
  end
  require("core").start()
  util.notify("Config reloaded")
end

return M
