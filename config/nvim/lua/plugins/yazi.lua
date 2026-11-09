vim.pack.add { "https://github.com/mikavilpas/yazi.nvim" }
vim.pack.add { "https://github.com/nvim-lua/plenary.nvim" }

require("yazi").setup({
  open_for_directories = true,
})

local function yazi_cd(scope)
  return function()
    local win = vim.api.nvim_get_current_win()
    local tab = vim.api.nvim_get_current_tabpage()

    require("yazi").yazi({
      change_neovim_cwd_on_close = false,
      hooks = {
        yazi_closed_successfully = function(_, _, state)
          local dir = state.last_directory and tostring(state.last_directory)
          if not dir then return end
          dir = vim.fn.fnameescape(dir)

          vim.schedule(function()
            if scope == "global" then
              vim.cmd("cd " .. dir)
            elseif scope == "tab" then
              vim.api.nvim_set_current_tabpage(tab)
              vim.cmd("tcd " .. dir)
            elseif scope == "window" and vim.api.nvim_win_is_valid(win) then
              vim.api.nvim_win_call(win, function()
                vim.cmd("lcd " .. dir)
              end)
            end
            vim.notify("Window cwd (" .. scope .. "): " .. vim.fn.fnamemodify(dir, ":~"), vim.log.levels.INFO, { title = "Yazi" })
          end)
        end,
      },
    })
  end
end

vim.keymap.set("n", "<leader>e", "<cmd>Yazi<cr>", { desc = "Open yazi at current file" })
vim.keymap.set("n", "<leader>Eg", yazi_cd("global"), { desc = "Yazi → global cwd" })
vim.keymap.set("n", "<leader>Et", yazi_cd("tab"),    { desc = "Yazi → tab cwd" })
vim.keymap.set("n", "<leader>Ew", yazi_cd("window"), { desc = "Yazi → window cwd" })

