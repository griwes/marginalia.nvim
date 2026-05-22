vim.g.mapleader = ' '
vim.g.maplocalleader = ' '

vim.opt.runtimepath:prepend(vim.fn.getcwd())

local lazypath = vim.fn.stdpath('data') .. '/lazy/lazy.nvim'

if vim.fn.isdirectory(lazypath) == 0 then
    vim.fn.system({
        'git',
        'clone',
        '--filter=blob:none',
        'https://github.com/folke/lazy.nvim.git',
        '--branch=stable',
        lazypath,
    })
end

vim.opt.runtimepath:prepend(lazypath)

require('lazy').setup({
    { dir = vim.fn.getcwd(), lazy = false },
    { 'nvim-lua/plenary.nvim', lazy = false },
}, {
    root = vim.fn.stdpath('data') .. '/lazy',
    lockfile = vim.fn.stdpath('config') .. '/lazy-lock.json',
})
