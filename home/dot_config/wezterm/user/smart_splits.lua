local M = {}

local direction_keys = {
  h = "Left",
  j = "Down",
  k = "Up",
  l = "Right",
}

local function is_vim(pane)
  local ok, user_vars = pcall(function()
    return pane:get_user_vars()
  end)

  return ok and user_vars and user_vars.IS_NVIM == "true"
end

local function pane_count(window)
  local ok, panes = pcall(function()
    return window:active_tab():panes()
  end)

  if not ok or not panes then
    return 0
  end

  return #panes
end

local function split_nav(wezterm, resize_or_move, key)
  local mods = resize_or_move == "resize" and "META" or "CTRL"

  return {
    key = key,
    mods = mods,
    action = wezterm.action_callback(function(window, pane)
      if is_vim(pane) or pane_count(window) == 1 then
        window:perform_action({
          SendKey = {
            key = key,
            mods = mods,
          },
        }, pane)
        return
      end

      if resize_or_move == "resize" then
        window:perform_action({
          AdjustPaneSize = {
            direction_keys[key],
            3,
          },
        }, pane)
      else
        window:perform_action({
          ActivatePaneDirection = direction_keys[key],
        }, pane)
      end
    end),
  }
end

function M.sync(config, wezterm)
  config.keys = config.keys or {}

  for _, key in ipairs({ "h", "j", "k", "l" }) do
    table.insert(config.keys, split_nav(wezterm, "move", key))
  end

  for _, key in ipairs({ "h", "j", "k", "l" }) do
    table.insert(config.keys, split_nav(wezterm, "resize", key))
  end
end

return M
