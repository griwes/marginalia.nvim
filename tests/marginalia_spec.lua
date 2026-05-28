describe('marginalia', function()
    local function buffer_keymap(bufnr, lhs)
        for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(bufnr, 'n')) do
            if mapping.lhs == lhs then
                return mapping
            end
        end

        return nil
    end

    local function listed_buffer()
        local bufnr = vim.api.nvim_create_buf(true, false)

        vim.bo[bufnr].swapfile = false
        return bufnr
    end

    after_each(function()
        require('marginalia').setup({ enabled = false })
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

    it('detaches attached windows when setup disables the plugin', function()
        local plugin = require('marginalia')
        local window = require('marginalia.window')
        local bufnr = listed_buffer()
        local original_bufnr = vim.api.nvim_get_current_buf()
        local original_height = vim.api.nvim_win_get_height(0)
        local original_conceallevel = vim.wo.conceallevel
        local original_scrolloff = vim.wo.scrolloff
        local lines = {}

        for row = 1, 40 do
            lines[row] = 'line ' .. row
        end

        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
        vim.api.nvim_win_set_buf(0, bufnr)
        vim.api.nvim_win_set_height(0, 8)
        vim.wo.conceallevel = 0
        vim.wo.scrolloff = 4
        vim.api.nvim_win_set_cursor(0, { 12, 0 })
        vim.fn.winrestview({ topline = 10 })

        assert.is_true(window.attach(0, {
            viewport = { respect_scrolloff = false },
            frames = { { row = 1 } },
        }))
        assert.are.equal(2, vim.wo.conceallevel)
        assert.are.equal(0, vim.wo.scrolloff)

        plugin.setup({ enabled = false })

        assert.is_nil(plugin.window_state())
        assert.are.equal(0, vim.wo.conceallevel)
        assert.are.equal(4, vim.wo.scrolloff)

        vim.api.nvim_win_set_buf(0, original_bufnr)
        vim.api.nvim_win_set_height(0, original_height)
        vim.wo.conceallevel = original_conceallevel
        vim.wo.scrolloff = original_scrolloff
        vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('keeps mouse mappings aligned with enable toggle and disable', function()
        local plugin = require('marginalia')
        local bufnr = listed_buffer()
        local original_bufnr = vim.api.nvim_get_current_buf()

        vim.api.nvim_win_set_buf(0, bufnr)
        plugin.setup({ auto_attach = false, input = { mouse_scroll = true } })

        assert.is_nil(buffer_keymap(bufnr, '<ScrollWheelUp>'))
        assert.is_nil(buffer_keymap(bufnr, '<ScrollWheelDown>'))
        assert.is_true(plugin.toggle())
        assert.is_not_nil(buffer_keymap(bufnr, '<ScrollWheelUp>'))
        assert.is_not_nil(buffer_keymap(bufnr, '<ScrollWheelDown>'))
        assert.is_false(plugin.toggle())
        assert.is_nil(buffer_keymap(bufnr, '<ScrollWheelUp>'))
        assert.is_nil(buffer_keymap(bufnr, '<ScrollWheelDown>'))
        assert.is_true(plugin.enable())
        assert.is_not_nil(buffer_keymap(bufnr, '<ScrollWheelUp>'))
        assert.is_not_nil(buffer_keymap(bufnr, '<ScrollWheelDown>'))

        plugin.disable()

        assert.is_nil(buffer_keymap(bufnr, '<ScrollWheelUp>'))
        assert.is_nil(buffer_keymap(bufnr, '<ScrollWheelDown>'))

        vim.api.nvim_win_set_buf(0, original_bufnr)
        vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('does not overwrite or delete user mouse mappings', function()
        local plugin = require('marginalia')
        local bufnr = listed_buffer()
        local original_bufnr = vim.api.nvim_get_current_buf()
        local user_up = function()
            return '<Ignore>'
        end
        local user_down = function()
            return '<Ignore>'
        end

        vim.api.nvim_win_set_buf(0, bufnr)
        vim.keymap.set('n', '<ScrollWheelUp>', user_up, { buffer = bufnr, expr = true })
        plugin.setup({ auto_attach = false, input = { mouse_scroll = true } })
        plugin.enable()

        assert.are.equal(user_up, buffer_keymap(bufnr, '<ScrollWheelUp>').callback)

        vim.keymap.set('n', '<ScrollWheelDown>', user_down, { buffer = bufnr, expr = true })
        plugin.disable()

        assert.are.equal(user_up, buffer_keymap(bufnr, '<ScrollWheelUp>').callback)
        assert.are.equal(user_down, buffer_keymap(bufnr, '<ScrollWheelDown>').callback)

        vim.keymap.del('n', '<ScrollWheelUp>', { buffer = bufnr })
        vim.keymap.del('n', '<ScrollWheelDown>', { buffer = bufnr })
        vim.api.nvim_win_set_buf(0, original_bufnr)
        vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('moves owned mouse mappings when an attached window changes buffers', function()
        local plugin = require('marginalia')
        local first_bufnr = listed_buffer()
        local second_bufnr = listed_buffer()
        local original_bufnr = vim.api.nvim_get_current_buf()

        vim.api.nvim_win_set_buf(0, first_bufnr)
        plugin.setup({ auto_attach = false, input = { mouse_scroll = true } })
        plugin.enable()

        assert.is_not_nil(buffer_keymap(first_bufnr, '<ScrollWheelUp>'))

        vim.api.nvim_win_set_buf(0, second_bufnr)

        assert.is_nil(buffer_keymap(first_bufnr, '<ScrollWheelUp>'))
        assert.is_not_nil(buffer_keymap(second_bufnr, '<ScrollWheelUp>'))

        plugin.disable()
        vim.api.nvim_win_set_buf(0, original_bufnr)
        vim.api.nvim_buf_delete(first_bufnr, { force = true })
        vim.api.nvim_buf_delete(second_bufnr, { force = true })
    end)

    it('does not auto-attach terminal URI or unlisted plugin buffers', function()
        local plugin = require('marginalia')
        local original_bufnr = vim.api.nvim_get_current_buf()
        local terminal_bufnr = listed_buffer()
        local uri_bufnr = listed_buffer()
        local plugin_bufnr = vim.api.nvim_create_buf(false, true)

        plugin.setup({ enabled = false })
        vim.api.nvim_open_term(terminal_bufnr, {})
        vim.api.nvim_win_set_buf(0, terminal_bufnr)
        plugin.setup({ auto_attach = true })
        assert.is_nil(plugin.window_state())

        plugin.setup({ enabled = false })
        vim.api.nvim_buf_set_name(uri_bufnr, 'marginalia-test://fixture')
        vim.api.nvim_win_set_buf(0, uri_bufnr)
        plugin.setup({ auto_attach = true })
        assert.is_nil(plugin.window_state())

        plugin.setup({ enabled = false })
        vim.api.nvim_win_set_buf(0, plugin_bufnr)
        plugin.setup({ auto_attach = true })
        assert.is_nil(plugin.window_state())

        vim.api.nvim_win_set_buf(0, original_bufnr)
        vim.api.nvim_buf_delete(terminal_bufnr, { force = true })
        vim.api.nvim_buf_delete(uri_bufnr, { force = true })
        vim.api.nvim_buf_delete(plugin_bufnr, { force = true })
    end)

    it('detaches and removes owned mappings when entering an unsuitable buffer', function()
        local plugin = require('marginalia')
        local file_bufnr = listed_buffer()
        local plugin_bufnr = vim.api.nvim_create_buf(false, true)
        local original_bufnr = vim.api.nvim_get_current_buf()

        vim.api.nvim_win_set_buf(0, file_bufnr)
        plugin.setup({ auto_attach = true, input = { mouse_scroll = true } })

        assert.is_not_nil(plugin.window_state())
        assert.is_not_nil(buffer_keymap(file_bufnr, '<ScrollWheelUp>'))

        vim.api.nvim_win_set_buf(0, plugin_bufnr)

        assert.is_nil(plugin.window_state())
        assert.is_nil(buffer_keymap(file_bufnr, '<ScrollWheelUp>'))

        vim.api.nvim_win_set_buf(0, original_bufnr)
        vim.api.nvim_buf_delete(file_bufnr, { force = true })
        vim.api.nvim_buf_delete(plugin_bufnr, { force = true })
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
