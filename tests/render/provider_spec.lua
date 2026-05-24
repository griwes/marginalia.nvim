local render_apply = require('marginalia.render.apply')
local render_provider = require('marginalia.render.provider')

describe('marginalia.render.provider', function()
    local function screen_text(row, col, width)
        local text = {}

        for index = 0, width - 1 do
            text[#text + 1] = vim.fn.screenstring(row, col + index)
        end

        return table.concat(text)
    end

    it('installs the provider idempotently', function()
        assert.has_no.errors(function()
            render_provider.install()
            render_provider.install()
        end)
    end)

    it('records window plans without immediate durable conceal marks', function()
        local bufnr = vim.api.nvim_create_buf(false, true)
        local state = {
            winid = vim.api.nvim_get_current_win(),
            bufnr = bufnr,
            identity = {
                bufnr = bufnr,
            },
        }

        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'one', 'two', 'three' })
        render_provider.update_window(state, {
            { start_row = 2, end_row = 2 },
        })

        assert.are.same({}, vim.api.nvim_buf_get_extmarks(bufnr, render_provider.namespace(), 0, -1, {}))
        assert.are.same({
            { start_row = 2, end_row = 2 },
        }, render_provider.debug_window(state.winid).hidden_ranges)

        render_provider.clear_window(state)
        vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('materializes conceal-line extmarks through the provider callback', function()
        local bufnr = vim.api.nvim_create_buf(false, true)
        local state = {
            winid = vim.api.nvim_get_current_win(),
            bufnr = bufnr,
            identity = {
                bufnr = bufnr,
            },
        }

        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'one', 'two', 'three', 'four' })
        render_provider.update_window(state, {
            { start_row = 2, end_row = 3 },
        })
        render_provider._on_conceal_line('conceal_line', state.winid, bufnr, 1)

        local marks = vim.api.nvim_buf_get_extmarks(bufnr, render_provider.namespace(), 0, -1, { details = true })

        assert.are.equal(1, #marks)
        assert.are.equal('', marks[1][4].conceal_lines)
        assert.are.equal(1, marks[1][2])
        assert.are.equal(2, marks[1][4].end_row)

        render_provider.clear_window(state)
        vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('does not materialize provider marks for non-matching windows or buffers', function()
        local bufnr = vim.api.nvim_create_buf(false, true)
        local other_bufnr = vim.api.nvim_create_buf(false, true)
        local state = {
            winid = vim.api.nvim_get_current_win(),
            bufnr = bufnr,
            identity = {
                bufnr = bufnr,
            },
        }

        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'one', 'two', 'three' })
        vim.api.nvim_buf_set_lines(other_bufnr, 0, -1, false, { 'alpha', 'beta' })
        render_provider.update_window(state, {
            { start_row = 2, end_row = 2 },
        })
        render_provider._on_conceal_line('conceal_line', state.winid + 1, bufnr, 1)
        render_provider._on_conceal_line('conceal_line', state.winid, other_bufnr, 1)

        assert.are.same({}, vim.api.nvim_buf_get_extmarks(bufnr, render_provider.namespace(), 0, -1, {}))
        assert.are.same({}, vim.api.nvim_buf_get_extmarks(other_bufnr, render_provider.namespace(), 0, -1, {}))

        render_provider.clear_window(state)
        vim.api.nvim_buf_delete(bufnr, { force = true })
        vim.api.nvim_buf_delete(other_bufnr, { force = true })
    end)

    it('does not materialize provider marks for visible rows', function()
        local bufnr = vim.api.nvim_create_buf(false, true)
        local state = {
            winid = vim.api.nvim_get_current_win(),
            bufnr = bufnr,
            identity = {
                bufnr = bufnr,
            },
        }

        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'one', 'two', 'three' })
        render_provider.update_window(state, {
            { start_row = 2, end_row = 2 },
        })
        render_provider._on_conceal_line('conceal_line', state.winid, bufnr, 0)

        assert.are.same({}, vim.api.nvim_buf_get_extmarks(bufnr, render_provider.namespace(), 0, -1, {}))

        render_provider.clear_window(state)
        vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('clears transient provider marks at window redraw boundaries', function()
        local bufnr = vim.api.nvim_create_buf(false, true)
        local winid = vim.api.nvim_get_current_win()
        local state = {
            winid = winid,
            bufnr = bufnr,
            identity = {
                bufnr = bufnr,
            },
        }

        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'one', 'two', 'three' })
        render_provider.update_window(state, {
            { start_row = 2, end_row = 2 },
        })
        render_provider._on_conceal_line('conceal_line', winid, bufnr, 1)

        assert.are.equal(1, #vim.api.nvim_buf_get_extmarks(bufnr, render_provider.namespace(), 0, -1, {}))

        assert.is_true(render_provider._on_win('win', winid, bufnr))
        assert.are.same({}, vim.api.nvim_buf_get_extmarks(bufnr, render_provider.namespace(), 0, -1, {}))

        render_provider.clear_window(state)
        vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('clears provider state tracked by window state', function()
        local bufnr = vim.api.nvim_create_buf(false, true)
        local ns = render_apply.namespace('test.state-clear')
        local winid = vim.api.nvim_get_current_win()

        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'one', 'two', 'three' })
        local state = {
            winid = winid,
            bufnr = bufnr,
            ns = ns,
            identity = {
                bufnr = bufnr,
            },
            render = {},
        }

        render_provider.update_window(state, {
            { start_row = 1, end_row = 1 },
        })
        render_provider._on_conceal_line('conceal_line', winid, bufnr, 0)
        render_apply.clear_state(state)

        assert.are.same({}, vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {}))
        assert.are.same({}, vim.api.nvim_buf_get_extmarks(bufnr, render_provider.namespace(), 0, -1, {}))
        assert.is_nil(render_provider.debug_window(winid))

        vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('leaves the row after a hidden range visible on screen', function()
        local bufnr = vim.api.nvim_create_buf(false, true)
        local previous_bufnr = vim.api.nvim_get_current_buf()
        local previous_conceallevel = vim.wo.conceallevel
        local winid = vim.api.nvim_get_current_win()
        local state = {
            winid = winid,
            bufnr = bufnr,
            identity = {
                bufnr = bufnr,
            },
        }

        vim.api.nvim_set_current_buf(bufnr)
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'one', 'two', 'three', 'four', 'five' })
        vim.wo.conceallevel = 2

        render_provider.update_window(state, {
            { start_row = 2, end_row = 3 },
        })

        vim.cmd.redraw()

        assert.are.equal('one', screen_text(1, 1, 3))
        assert.are.equal('four', screen_text(2, 1, 4))
        assert.are.equal('five', screen_text(3, 1, 4))

        render_provider.clear_window(state)
        vim.wo.conceallevel = previous_conceallevel
        vim.api.nvim_set_current_buf(previous_bufnr)
        vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('keeps provider conceal decisions local to the rendering window', function()
        local bufnr = vim.api.nvim_create_buf(false, true)
        local previous_conceallevel = vim.wo.conceallevel

        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'one', 'two', 'three', 'four', 'five' })
        vim.api.nvim_win_set_buf(0, bufnr)
        vim.wo.conceallevel = 2
        vim.cmd('belowright split')

        local bottom = vim.api.nvim_get_current_win()
        local top = vim.fn.win_getid(vim.fn.winnr('#'))

        vim.api.nvim_win_set_buf(bottom, bufnr)
        vim.wo[bottom].conceallevel = 2
        vim.wo[top].conceallevel = 2
        vim.api.nvim_win_call(top, function()
            vim.fn.winrestview({ topline = 1 })
        end)
        vim.api.nvim_win_call(bottom, function()
            vim.fn.winrestview({ topline = 1 })
        end)

        local top_state = {
            winid = top,
            bufnr = bufnr,
            identity = {
                bufnr = bufnr,
            },
        }
        local bottom_state = {
            winid = bottom,
            bufnr = bufnr,
            identity = {
                bufnr = bufnr,
            },
        }

        render_provider.update_window(top_state, {
            { start_row = 2, end_row = 2 },
        })
        render_provider.update_window(bottom_state, {})
        vim.cmd.redraw()

        local top_row = vim.fn.getwininfo(top)[1].winrow
        local bottom_row = vim.fn.getwininfo(bottom)[1].winrow

        assert.are.equal('one', screen_text(top_row, 1, 3))
        assert.are.equal('three', screen_text(top_row + 1, 1, 5))
        assert.are.equal('one', screen_text(bottom_row, 1, 3))
        assert.are.equal('two', screen_text(bottom_row + 1, 1, 3))

        render_provider.clear_window(top_state)
        render_provider.clear_window(bottom_state)
        vim.api.nvim_win_close(bottom, true)
        vim.wo[top].conceallevel = previous_conceallevel
        vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
end)
