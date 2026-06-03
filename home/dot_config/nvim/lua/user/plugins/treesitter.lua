return {
  {
    "nvim-treesitter/nvim-treesitter",
    event = { "BufReadPost", "BufNewFile" },
    cmd = {
      "TSInstall",
      "TSInstallFromGrammar",
      "TSUpdate",
      "TSUninstall",
      "TSLog",
    },
    config = function(_, opts)
      require("nvim-treesitter").setup(opts)

      local group = vim.api.nvim_create_augroup("UserTreesitter", { clear = true })

      local function start(bufnr)
        if not vim.api.nvim_buf_is_loaded(bufnr) then
          return
        end

        local filetype = vim.bo[bufnr].filetype
        if filetype == "" then
          return
        end

        local lang = vim.treesitter.language.get_lang(filetype)
        if not lang then
          return
        end

        if not pcall(vim.treesitter.get_parser, bufnr, lang) then
          return
        end

        pcall(vim.treesitter.start, bufnr, lang)
        vim.bo[bufnr].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
      end

      vim.api.nvim_create_autocmd("FileType", {
        group = group,
        callback = function(args)
          start(args.buf)
        end,
      })

      for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        start(bufnr)
      end
    end,
  },
}
