vim.pack.add {
  "https://github.com/echasnovski/mini.surround",
  "https://github.com/echasnovski/mini.ai",
  "https://github.com/echasnovski/mini.icons",
  "https://github.com/echasnovski/mini.hipatterns",
}
require("mini.icons").setup()
require("mini.surround").setup()
require("mini.ai").setup()

local hi = require("mini.hipatterns")
hi.setup({
  highlighters = {
    todo  = { pattern = "%f[%w]()TODO()%f[%W]",  group = "MiniHipatternsTodo" },
    fixme = { pattern = "%f[%w]()FIXME()%f[%W]", group = "MiniHipatternsFixme" },
    hex_color = hi.gen_highlighter.hex_color(),
  },
})
