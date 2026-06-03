return {
  {
    "mason-org/mason.nvim",
    cmd = "Mason",
    opts = function()
      return {
        PATH = "prepend",
        ui = {
          border = "rounded",
        },
      }
    end,
  },
  {
    "mason-org/mason-lspconfig.nvim",
    dependencies = {
      "mason-org/mason.nvim",
      "neovim/nvim-lspconfig",
    },
    opts = {
      automatic_enable = true,
    },
  },
  {
    "neovim/nvim-lspconfig",
    dependencies = {
      "mason-org/mason.nvim",
      "saghen/blink.cmp",
    },
    config = function()
      vim.diagnostic.config({
        severity_sort = true,
        virtual_text = {
          spacing = 2,
          source = "if_many",
        },
        float = {
          border = "rounded",
          source = true,
        },
      })

      local ok, blink = pcall(require, "blink.cmp")
      if ok then
        vim.lsp.config("*", {
          capabilities = blink.get_lsp_capabilities(),
        })
      end
    end,
  },
  {
    "j-hui/fidget.nvim",
    opts = {},
  },
  {
    "stevearc/conform.nvim",
    opts = {
      format_on_save = function()
        return {
          timeout_ms = 500,
          lsp_format = "fallback",
        }
      end,
      formatters_by_ft = {
        lua = { "stylua" },
        sh = { "shfmt" },
        zsh = { "shfmt" },
      },
    },
  },
}
