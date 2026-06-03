local M = {}

function M.sync(config, wezterm)
  config.keys = {
    {
      key = "w",
      mods = "CTRL",
      action = wezterm.action.CloseCurrentTab({ confirm = false }),
    },
  }
end

return M
