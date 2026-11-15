-- Typst buffers: keys for the preview (mechanism: lua/core/typst_preview.lua).
vim.api.nvim_create_autocmd("FileType", {
  group = vim.api.nvim_create_augroup("user_typst", { clear = true }),
  pattern = "typst",
  callback = function(ev)
    local function map(lhs, rhs, desc)
      vim.keymap.set("n", lhs, rhs, { buffer = ev.buf, desc = desc })
    end
    local preview = function(fn)
      return function()
        require("core.typst_preview")[fn]()
      end
    end
    map("<leader>lp", preview("open"), "Typst preview (start / reopen)")
    map("<leader>lP", preview("stop"), "Typst preview stop")
    map("<leader>ls", function() require("core.typst_preview").sync(true) end, "Typst preview: scroll to cursor")
    map("<leader>ut", preview("toggle_theme"), "Typst preview: toggle light / dark")
    map("<leader>up", preview("follow"), "Typst preview: toggle follow cursor")
  end,
})
