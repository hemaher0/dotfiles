local M = {}

function M.sync(config, wezterm)
  config.initial_cols = 100
  config.initial_rows = 24

  config.font = wezterm.font_with_fallback({
    "Red Hat Mono",
    "D2CodingLigature Nerd Font",
  })

  config.font_size = 12
  config.color_scheme = "GitHub Dark"
  config.adjust_window_size_when_changing_font_size = false
  config.use_cap_height_to_scale_fallback_fonts = true

  config.window_decorations = "RESIZE"
  config.window_frame = {
    font_size = 10,
  }
  config.window_close_confirmation = "NeverPrompt"
  if wezterm.target_triple:find("windows") then
    config.skip_close_confirmation_for_processes_named = {
      "bash.exe",
      "sh.exe",
      "powershell.exe",
      "pwsh.exe",
      "cmd.exe",
      "ubuntu2404.exe",
    }
  else
    config.skip_close_confirmation_for_processes_named = {
      "bash",
      "sh",
    }
  end

  config.window_padding = {
    left = 4,
    right = 4,
    top = 2,
    bottom = 2,
  }

  config.front_end = "WebGpu"
  config.animation_fps = 60
  config.enable_kitty_keyboard = true
  config.scrollback_lines = 10000
  config.default_cursor_style = "SteadyBlock"
  config.check_for_updates = false
  config.automatically_reload_config = true
end

return M
