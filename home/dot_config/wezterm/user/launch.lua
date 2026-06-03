local M = {}

local function is_windows(wezterm)
  return wezterm.target_triple:find("windows") ~= nil
end

function M.apply(config, wezterm)
  if is_windows(wezterm) then
    config.default_prog = { "pwsh.exe", "-NoLogo" }
    config.launch_menu = {
      {
        label = "PowerShell",
        args = { "pwsh.exe", "-NoLogo" },
      },
      {
        label = "PowerShell (Admin)",
        args = {
          "pwsh.exe",
          "-Command",
          'Start-Process pwsh -Verb RunAs -ArgumentList "-NoLogo"',
        },
      },
      {
        label = "Ubuntu",
        args = { "ubuntu2404.exe" },
      },
    }
  else
    config.default_prog = { "/bin/bash" }
    config.launch_menu = {
      {
        label = "Bash",
        args = { "/bin/bash" },
      },
    }
  end
end

return M
