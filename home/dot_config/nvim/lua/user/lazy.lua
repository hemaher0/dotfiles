if vim.env.DOTFILES_NVIM_SKIP_PLUGINS == "1" then
  return
end

local function is_headless()
  return #vim.api.nvim_list_uis() == 0
end

local function fail_bootstrap(message, output)
  if output and output ~= "" then
    vim.api.nvim_echo({
      { message .. "\n", "ErrorMsg" },
      { output, "WarningMsg" },
    }, true, {})
  else
    vim.api.nvim_err_writeln(message)
  end

  if is_headless() then
    vim.cmd("cquit")
  end
end

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"

if not (vim.uv or vim.loop).fs_stat(lazypath) then
  if vim.fn.executable("git") == 0 then
    fail_bootstrap("git is required to install lazy.nvim")
    return
  end

  local lazyrepo = "https://github.com/folke/lazy.nvim.git"
  local output = vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "--branch=stable",
    lazyrepo,
    lazypath,
  })

  if vim.v.shell_error ~= 0 then
    fail_bootstrap("Failed to clone lazy.nvim:", output)
    return
  end
end

vim.opt.runtimepath:prepend(lazypath)

require("lazy").setup({
  { import = "user.plugins" },
}, {
  defaults = {
    lazy = false,
  },
  install = {
    missing = true,
    colorscheme = { "habamax" },
  },
  checker = {
    enabled = false,
  },
  change_detection = {
    notify = false,
  },
  performance = {
    rtp = {
      disabled_plugins = {
        "gzip",
        "matchit",
        "matchparen",
        "netrwPlugin",
        "tarPlugin",
        "tohtml",
        "tutor",
        "zipPlugin",
      },
    },
  },
})
