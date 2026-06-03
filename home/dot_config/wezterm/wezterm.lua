local wezterm = require("wezterm")

local config = wezterm.config_builder and wezterm.config_builder() or {}

package.path = wezterm.config_dir .. "/?.lua;" .. wezterm.config_dir .. "/?/init.lua;" .. package.path

for _, module in ipairs({
  "user.appearance",
  "user.launch",
  "user.keys",
  "user.smart_splits",
  "user.status",
}) do
  require(module).sync(config, wezterm)
end

local separator = package.config:sub(1, 1)
local local_path = wezterm.config_dir .. separator .. "user" .. separator .. "local.lua"
local local_file = io.open(local_path, "r")
if local_file then
  local_file:close()
  local local_config = require("user.local")
  local_config.sync(config, wezterm)
end

return config
