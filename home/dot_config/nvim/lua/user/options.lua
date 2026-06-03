vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

local opt = vim.opt

opt.number = true
opt.relativenumber = true
opt.cursorline = true
opt.signcolumn = "yes"
opt.termguicolors = true

opt.expandtab = true
opt.shiftwidth = 2
opt.softtabstop = 2
opt.tabstop = 2
opt.smartindent = true

opt.ignorecase = true
opt.smartcase = true
opt.inccommand = "split"
opt.hlsearch = true

opt.splitbelow = true
opt.splitright = true
opt.scrolloff = 8
opt.sidescrolloff = 8

opt.undofile = true
opt.updatetime = 250
opt.timeoutlen = 300
opt.completeopt = { "menu", "menuone", "noselect" }

opt.list = true
opt.listchars = {
  tab = "> ",
  trail = ".",
  nbsp = "+",
}

vim.api.nvim_create_autocmd("UIEnter", {
  once = true,
  callback = function()
    if vim.fn.has("clipboard") == 1 then
      opt.clipboard = "unnamedplus"
    end
  end,
})
