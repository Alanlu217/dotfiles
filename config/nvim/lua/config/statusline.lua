-- Default statusline layout, with the format status added on the right
vim.opt.statusline = table.concat({
  "%f %h%w%m%r",
  "%=",
  "%{v:lua.require'config.format'.status()}  ",
  "%-14.(%l,%c%V%) %P",
})
