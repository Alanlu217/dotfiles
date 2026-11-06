vim.pack.add { "https://github.com/echasnovski/mini.clue" }

local miniclue = require("mini.clue")

miniclue.setup({
  triggers = {
    -- Leader
    { mode = "n", keys = "<Leader>" },
    { mode = "x", keys = "<Leader>" },

    -- Built-in prefixes
    { mode = "n", keys = "g" },    { mode = "x", keys = "g" },
    { mode = "n", keys = "z" },    { mode = "x", keys = "z" },
    { mode = "n", keys = "[" },    { mode = "n", keys = "]" },
    { mode = "n", keys = "<C-w>" },
    { mode = "n", keys = "'" },    { mode = "n", keys = "`" },
    { mode = "n", keys = '"' },    { mode = "x", keys = '"' },
    { mode = "i", keys = "<C-r>" }, { mode = "c", keys = "<C-r>" },
    { mode = "i", keys = "<C-x>" },
  },

  clues = {
    -- Group labels
    { mode = "n", keys = "<Leader>c", desc = "+Code" },
    { mode = "n", keys = "<Leader>u", desc = "+UI" },

    miniclue.gen_clues.builtin_completion(),
    miniclue.gen_clues.g(),
    miniclue.gen_clues.marks(),
    miniclue.gen_clues.registers(),
    miniclue.gen_clues.windows(),
    miniclue.gen_clues.z(),
  },

  window = { delay = 100 },
})
