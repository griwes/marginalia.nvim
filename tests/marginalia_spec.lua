describe('marginalia', function()
    after_each(function()
        require('marginalia').disable()
    end)

    it('loads and exposes setup', function()
        local plugin = require('marginalia')

        assert.are.equal('function', type(plugin.setup))
        assert.are.equal('function', type(plugin.enable))
        assert.are.equal('function', type(plugin.disable))
        assert.are.equal('function', type(plugin.toggle))
        assert.are.equal('function', type(plugin.refresh))
        assert.are.equal('function', type(plugin.debug_snapshot))
    end)

    it('normalizes setup options', function()
        local plugin = require('marginalia')
        local resolved = plugin.setup({
            auto_attach = false,
            context = {
                max_depth = 2.9,
                skip_node_types = { 'chunk', custom = true, disabled = false },
            },
        })

        assert.are.equal(2, resolved.context.max_depth)
        assert.is_true(resolved.context.skip_node_types.chunk)
        assert.is_true(resolved.context.skip_node_types.custom)
        assert.is_nil(resolved.context.skip_node_types.disabled)
    end)

    it('normalizes grouped setup concerns', function()
        local plugin = require('marginalia')
        local resolved = plugin.setup({
            auto_attach = false,
            context = {
                max_depth = 1,
            },
            viewport = {
                respect_scrolloff = false,
                scope = 'full_buffer',
            },
            render = {
                conceallevel = 1,
                priority = 300,
            },
        })

        assert.are.equal(1, resolved.context.max_depth)
        assert.is_false(resolved.viewport.respect_scrolloff)
        assert.are.equal('full_buffer', resolved.viewport.scope)
        assert.are.equal(1, resolved.render.conceallevel)
        assert.are.equal(300, resolved.render.priority)
    end)

    it('installs user commands on setup', function()
        local plugin = require('marginalia')
        plugin.setup({ auto_attach = false })

        assert.is_not_nil(vim.api.nvim_get_commands({})['MarginaliaEnable'])
        assert.is_not_nil(vim.api.nvim_get_commands({})['MarginaliaDisable'])
        assert.is_not_nil(vim.api.nvim_get_commands({})['MarginaliaToggle'])
        assert.is_not_nil(vim.api.nvim_get_commands({})['MarginaliaRefresh'])
        assert.is_not_nil(vim.api.nvim_get_commands({})['MarginaliaDebug'])
    end)

    it('cleans window state when an attached window closes', function()
        local plugin = require('marginalia')
        local bufnr = vim.api.nvim_create_buf(false, true)
        local original_win = vim.api.nvim_get_current_win()

        plugin.setup({ auto_attach = false })
        vim.cmd('vsplit')

        local winid = vim.api.nvim_get_current_win()
        vim.api.nvim_win_set_buf(winid, bufnr)

        assert.is_true(plugin.enable(winid))
        assert.is_not_nil(plugin.window_state(winid))

        vim.api.nvim_set_current_win(original_win)
        vim.api.nvim_win_close(winid, true)
        vim.wait(100, function()
            return plugin.window_state(winid) == nil
        end)

        assert.is_nil(plugin.window_state(winid))

        vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
end)
