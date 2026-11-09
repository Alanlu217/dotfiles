vim.pack.add { "https://github.com/chomosuke/typst-preview.nvim" }
require("typst-preview").setup({
  get_main_file = function(path_of_buffer)
    local main = vim.fs.find("main.typ", {
      upward = true,
      path = vim.fs.dirname(path_of_buffer),
    })[1]
    return main or path_of_buffer
  end,
})
