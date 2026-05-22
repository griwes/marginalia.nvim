describe('marginalia', function()
    after_each(function()
        require('marginalia').disable()
    end)

    it('loads and exposes setup', function()
        local plugin = require('marginalia')

        assert.are.equal('function', type(plugin.setup))
        assert.are.equal('function', type(plugin.plan_hidden_ranges))
        assert.are.equal('function', type(plugin.enable))
        assert.are.equal('function', type(plugin.disable))
        assert.are.equal('function', type(plugin.toggle))
        assert.are.equal('function', type(plugin.refresh))
    end)

    it('normalizes setup options', function()
        local plugin = require('marginalia')
        local resolved = plugin.setup({
            auto_attach = false,
            max_depth = 2.9,
            skip_node_types = { 'chunk', custom = true, disabled = false },
        })

        assert.are.equal(2, resolved.max_depth)
        assert.is_true(resolved.skip_node_types.chunk)
        assert.is_true(resolved.skip_node_types.custom)
        assert.is_nil(resolved.skip_node_types.disabled)
    end)

    it('returns an empty result when no parser is available', function()
        local plugin = require('marginalia')
        plugin.setup({ auto_attach = false })
        local bufnr = vim.api.nvim_create_buf(false, true)
        local winid = vim.api.nvim_get_current_win()
        local previous = vim.api.nvim_win_get_buf(winid)

        vim.api.nvim_win_set_buf(winid, bufnr)
        vim.bo[bufnr].filetype = ''

        local result = plugin.get_context({ bufnr = bufnr, winid = winid, lang = 'marginalia_missing_language' })

        vim.api.nvim_win_set_buf(winid, previous)
        vim.api.nvim_buf_delete(bufnr, { force = true })

        assert.are.same({}, result.frames)
        assert.are.equal('no_parser', result.reason)
    end)

    it('installs user commands on setup', function()
        local plugin = require('marginalia')
        plugin.setup({ auto_attach = false })

        assert.is_not_nil(vim.api.nvim_get_commands({})['MarginaliaEnable'])
        assert.is_not_nil(vim.api.nvim_get_commands({})['MarginaliaDisable'])
        assert.is_not_nil(vim.api.nvim_get_commands({})['MarginaliaToggle'])
        assert.is_not_nil(vim.api.nvim_get_commands({})['MarginaliaRefresh'])
    end)
end)
