local M = {}

function M.apply(config, wezterm)
  config.keys = {
    {
      key = "w",
      mods = "CTRL",
      action = wezterm.action.CloseCurrentTab({ confirm = false }),
    },
  }
end

return M
