local M = {}

local msys2_root = "C:/msys64"
local msys2_env = {
  CHERE_INVOKING = "1",
  MSYSTEM = "UCRT64",
  MSYS2_PATH_TYPE = "inherit",
}

local function with_env_args(exe, args)
  local command_args = {
    msys2_root .. "/usr/bin/env.exe",
  }

  for key, value in pairs(msys2_env) do
    table.insert(command_args, key .. "=" .. value)
  end

  table.insert(command_args, msys2_root .. exe)

  for _, arg in ipairs(args or {}) do
    table.insert(command_args, arg)
  end

  return command_args
end

local function command(label, exe, args)
  local spawn = {
    label = label,
    args = { msys2_root .. exe },
    set_environment_variables = msys2_env,
  }

  for _, arg in ipairs(args or {}) do
    table.insert(spawn.args, arg)
  end

  return spawn
end

function M.zsh()
  return command("MSYS2 Zsh", "/usr/bin/zsh.exe", { "-l" })
end

function M.default_zsh_args()
  return with_env_args("/usr/bin/zsh.exe", { "-l" })
end

function M.bash()
  return command("MSYS2 Bash", "/usr/bin/bash.exe", { "-l" })
end

return M
