local M = {}

function M.sync(config, wezterm)
  local min_tab_width = 50

  wezterm.on("format-tab-title", function(tab, tabs, panes, current_config, hover, max_width)
    local title = tab.active_pane.title
    local current_width = wezterm.column_width(title)

    if current_width < min_tab_width then
      title = wezterm.pad_right(title, min_tab_width)
    end

    return {
      { Text = " " .. title .. " " },
    }
  end)
end

return M
