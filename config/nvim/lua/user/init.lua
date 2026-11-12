-- Entry point for user space. Loaded by core after all framework features are
-- ready. Order matters: options (incl. leader) -> theme -> keymaps -> extras.
-- Each module is loaded safely, so a typo in one never breaks the rest.
local safe_require = require("core.util").safe_require

for _, mod in ipairs({
  "user.options",
  "user.theme",
  "user.keymaps",
  "user.spell",
}) do
  safe_require(mod)
end
