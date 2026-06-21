local M = {}

local function is_windows(wezterm)
  return wezterm.target_triple:find("windows") ~= nil
end

function M.sync(config, wezterm)
  if is_windows(wezterm) then
    local user_profile = os.getenv("USERPROFILE") or ""
    local msys2_zsh = user_profile .. "\\.local\\bin\\msys2-zsh.cmd"

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
        label = "MSYS2 zsh",
        args = { msys2_zsh },
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
