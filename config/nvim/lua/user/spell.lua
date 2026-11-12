-- Per-buffer spell checking: the toggle follows the buffer, not the window.
local function sync(buf)
  vim.wo.spell = vim.b[buf].spell_enabled == true
end

vim.keymap.set("n", "<leader>us", function()
  local enabled = not vim.b.spell_enabled
  vim.b.spell_enabled = enabled
  vim.wo.spell = enabled
  vim.notify("Spell check " .. (enabled and "on" or "off"))
end, { desc = "Toggle spell check (buffer)" })

vim.api.nvim_create_autocmd("BufWinEnter", {
  group = vim.api.nvim_create_augroup("user_spell", { clear = true }),
  callback = function(ev)
    sync(ev.buf)
  end,
})
