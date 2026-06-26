local M = {}

local function is_windows(wezterm)
  return wezterm.target_triple:find("windows") ~= nil
end

function M.sync(config, wezterm)
  if is_windows(wezterm) then
    local msys2 = require("user.msys2")
    local msys2_zsh = msys2.zsh()
    local msys2_bash = msys2.bash()
    local windows_home = os.getenv("USERPROFILE") or os.getenv("HOME")

    config.default_prog = msys2.default_zsh_args()
    config.default_cwd = windows_home
    config.launch_menu = {
      msys2_zsh,
      msys2_bash,
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
