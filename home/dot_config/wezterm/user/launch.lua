local M = {}

local function is_windows(wezterm)
  return wezterm.target_triple:find("windows") ~= nil
end

function M.sync(config, wezterm)
  if is_windows(wezterm) then
    local msys2_root = "C:/msys64"
    local msys2_zsh = msys2_root .. "/usr/bin/zsh.exe"
    local msys2_bash = msys2_root .. "/usr/bin/bash.exe"
    local windows_home = os.getenv("USERPROFILE") or os.getenv("HOME")

    config.default_prog = { msys2_zsh, "-l" }
    config.default_cwd = windows_home
    config.launch_menu = {
      {
        label = "MSYS2 Zsh",
        args = { msys2_zsh, "-l" },
      },
      {
        label = "MSYS2 Bash",
        args = { msys2_bash, "-l" },
      },
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
