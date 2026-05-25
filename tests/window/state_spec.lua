local window_state = require('marginalia.window.state')

describe('marginalia.window.state', function()
    it('drops invalid windows when attachment state is queried', function()
        vim.cmd('split')

        local winid = vim.api.nvim_get_current_win()

        window_state.ensure(winid)
        assert.is_true(window_state.is_attached(winid))

        vim.api.nvim_win_close(winid, true)

        assert.is_false(window_state.is_attached(winid))
        assert.is_nil(window_state.get(winid))
    end)

    it('creates explicit state submodels for each runtime concern', function()
        local winid = vim.api.nvim_get_current_win()
        local state = assert(window_state.ensure(winid))

        assert.are.equal(winid, state.identity.winid)
        assert.are.equal(state.bufnr, state.identity.bufnr)
        assert.are.equal(state.ns, state.identity.ns)
        assert.are.equal('table', type(state.options))
        assert.are.equal('table', type(state.cursor))
        assert.are.equal('table', type(state.semantic))
        assert.are.equal('table', type(state.viewport))
        assert.are.equal('table', type(state.render))
        assert.are.equal('table', type(state.transaction))

        window_state.remove(winid)
    end)

    it('records cursor rows and queries hidden prior rows', function()
        local winid = vim.api.nvim_get_current_win()
        local state = assert(window_state.ensure(winid))

        window_state.record_cursor_row(state, 12, 4)

        assert.are.equal(12, state.cursor.row)
        assert.are.equal(4, state.cursor.physical_row)

        state.render.plan = {
            visible_rows = {},
            hidden_ranges = {
                { start_row = 3, end_row = 5 },
            },
        }

        assert.is_true(window_state.row_was_hidden(state, 4))
        assert.is_false(window_state.row_was_hidden(state, 6))

        window_state.remove(winid)
    end)

    it('resolves effective scrolloff from state options', function()
        local winid = vim.api.nvim_get_current_win()
        local state = assert(window_state.ensure(winid))
        local previous_global_scrolloff = vim.go.scrolloff
        local previous_window_scrolloff = vim.wo[winid].scrolloff

        vim.wo[winid].scrolloff = 3
        assert.are.equal(3, window_state.effective_scrolloff(state))

        state.options.scrolloff_suppressed = true
        state.options.original_scrolloff = 2
        state.options.scrolloff_restore_global = false
        assert.are.equal(2, window_state.effective_scrolloff(state))

        vim.go.scrolloff = 5
        state.options.scrolloff_restore_global = true
        assert.are.equal(5, window_state.effective_scrolloff(state))

        vim.go.scrolloff = previous_global_scrolloff
        vim.wo[winid].scrolloff = previous_window_scrolloff
        window_state.remove(winid)
    end)

    it('records apply results in structured state fields', function()
        local state = {
            cursor = {},
            viewport = {},
            render = {},
            transaction = {
                pending_option_echoes = {
                    scrolloff = true,
                },
            },
        }
        local plan = {
            visible_rows = { 1, 3 },
            hidden_ranges = {
                { start_row = 2, end_row = 2 },
            },
            projection = {},
        }

        window_state.record_apply_result(state, {
            plan = plan,
            context_topline = 1,
            logical_topline = 3,
            raw_topline = 4,
            previous_raw_topline = 2,
            post_apply_view = { topline = 4 },
            cursor_row = 8,
            cursor_winline = 5,
            scrolloff = {
                user = 0,
                effective = 0,
            },
        })
        assert.are.equal(plan, state.render.plan)
        assert.are.equal(1, state.viewport.context_topline)
        assert.are.equal(3, state.viewport.logical_topline)
        assert.are.equal(4, state.viewport.raw_topline)
        assert.are.equal(plan.projection, state.viewport.applied_projection)
        assert.are.same(
            { visible_rows = { 1, 3 }, hidden_ranges = { { start_row = 2, end_row = 2 } } },
            state.render.artifact
        )
        assert.are.equal(8, state.cursor.row)
        assert.are.equal(5, state.cursor.physical_row)
        assert.are.equal(1, state.transaction.epoch)
        assert.are.equal(1, state.transaction.expected_scroll_echo.epoch)
        assert.are.equal(4, state.transaction.expected_scroll_echo.raw_topline)
        assert.are.same({
            [2] = true,
            [4] = true,
        }, state.transaction.expected_scroll_echo.raw_toplines)
        assert.are.same({ scrolloff = true }, state.transaction.expected_option_echo.options)
        assert.is_nil(state.transaction.pending_option_echoes)
    end)

    it('does not record impossible empty option echoes', function()
        local state = {
            cursor = {},
            viewport = {},
            render = {},
            transaction = {},
        }
        local plan = {
            visible_rows = {},
            hidden_ranges = {},
            projection = {},
        }

        window_state.record_apply_result(state, {
            plan = plan,
            logical_topline = 1,
            raw_topline = 1,
            post_apply_view = { topline = 1 },
            cursor_row = 1,
            cursor_winline = 1,
        })

        assert.is_nil(state.transaction.expected_option_echo)
    end)

    it('records empty results in structured state fields', function()
        local state = {
            cursor = {},
            viewport = {},
            render = {},
        }

        window_state.record_empty_result(state, {
            cursor_row = 7,
            raw_topline = 5,
        })

        assert.are.same({ visible_rows = {}, hidden_ranges = {} }, state.render.plan)
        assert.are.equal(7, state.cursor.row)
        assert.are.equal(5, state.viewport.raw_topline)
    end)
end)
