local M = {}

function M.check()
    vim.health.start('marginalia.nvim')

    if vim.fn.has('nvim-0.11') == 1 then
        vim.health.ok('Neovim 0.11 or newer')
    else
        vim.health.error('Neovim 0.11 or newer is required')
    end

    if type(vim.api.nvim__ns_set) == 'function' then
        vim.health.ok('Experimental nvim__ns_set API is available')
    else
        vim.health.warn('nvim__ns_set is unavailable; conceal rendering will remain disabled')
    end

    local lang = vim.treesitter.language.get_lang(vim.bo.filetype)
    if vim.bo.filetype == '' then
        vim.health.info('Open a source buffer to check its Tree-sitter parser')
    elseif lang and pcall(vim.treesitter.language.inspect, lang) then
        vim.health.ok('Tree-sitter parser is available for ' .. vim.bo.filetype)
    else
        vim.health.warn('No Tree-sitter parser is available for ' .. vim.bo.filetype)
    end
end

return M
