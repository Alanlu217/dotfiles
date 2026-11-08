vim.pack.add { "https://github.com/echasnovski/mini.clue" }

local miniclue = require("mini.clue")

-- Copy the built-in <C-w> clues to the <Leader>w prefix (keys and submode postkeys)
local function leader_windows(opts)
  local out = {}
  for _, c in ipairs(miniclue.gen_clues.windows(opts)) do
    local copy = vim.deepcopy(c)
    copy.keys = (copy.keys:gsub("^<C%-w>", "<Leader>w"))
    if copy.postkeys then
      copy.postkeys = (copy.postkeys:gsub("^<C%-w>", "<Leader>w"))
    end
    out[#out + 1] = copy
  end
  return out
end

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
    { mode = "n", keys = "<Leader>t", desc = "+Tabs" },
    { mode = "n", keys = "<Leader>u", desc = "+UI" },
    { mode = "n", keys = "<Leader>w", desc = "+Windows" },
    { mode = "n", keys = "<Leader>q", desc = "+Saved cwd" },

    miniclue.gen_clues.builtin_completion(),
    miniclue.gen_clues.g(),
    miniclue.gen_clues.marks(),
    miniclue.gen_clues.registers(),
    miniclue.gen_clues.windows({ submode_resize = true }), -- <C-w> clues
    leader_windows({ submode_resize = true }),             -- <Leader>w clues
    miniclue.gen_clues.z(),
  },

  window = { delay = 0 },
})
