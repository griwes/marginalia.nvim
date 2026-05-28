local render_apply = require('marginalia.render.apply')
local render_provider = require('marginalia.render.provider')
local window_apply = require('marginalia.window.apply')

describe('marginalia.render.provider', function()
    local original_ns_set
    local original_notify_once

    before_each(function()
        original_ns_set = vim.api.nvim__ns_set
        original_notify_once = vim.notify_once
    end)

    after_each(function()
        vim.api.nvim__ns_set = original_ns_set
        vim.notify_once = original_notify_once
    end)

    local function screen_text(row, col, width)
        local text = {}

        for index = 0, width - 1 do
            text[#text + 1] = vim.fn.screenstring(row, col + index)
        end

        return table.concat(text)
    end

    local function state_for(winid, bufnr, suffix)
        local ns = render_apply.namespace('test.provider.' .. suffix)

        return {
            winid = winid,
            bufnr = bufnr,
            ns = ns,
            identity = {
                bufnr = bufnr,
            },
            render = {},
        }
    end

    it('installs idempotently without registering a redraw provider', function()
        assert.has_no.errors(function()
            render_provider.install()
            render_provider.install()
        end)
    end)

    it('fails closed when per-window namespace scoping is unavailable', function()
        local bufnr = vim.api.nvim_create_buf(false, true)
        local winid = vim.api.nvim_get_current_win()
        local state = state_for(winid, bufnr, 'unsupported')
        local notifications = {}

        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'one', 'two', 'three', 'four' })
        vim.api.nvim__ns_set = nil
        vim.notify_once = function(message)
            notifications[#notifications + 1] = message
        end

        local rendered, reason = render_provider.update_window(state, {
            { start_row = 2, end_row = 3 },
        })
        local plan = window_apply.apply_projection({
            bufnr = bufnr,
            state = state,
            projection = {
                visible_rows = { 1, 4 },
                conceal_scope = { start_row = 1, end_row = 4 },
            },
        })

        assert.is_false(rendered)
        assert.are.equal('nvim__ns_set is unavailable; per-window conceal is disabled', reason)
        assert.are.same({}, plan.hidden_ranges)
        assert.are.equal(reason, plan.render_error)
        assert.are.same({}, vim.api.nvim_buf_get_extmarks(bufnr, state.ns, 0, -1, {}))
        assert.is_nil(render_provider.debug_window(winid))
        assert.is_true(#notifications > 0)

        vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('materializes conceal-line extmarks immediately in a window namespace', function()
        local bufnr = vim.api.nvim_create_buf(false, true)
        local winid = vim.api.nvim_get_current_win()
        local state = state_for(winid, bufnr, 'materialize')

        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'one', 'two', 'three', 'four' })
        render_provider.update_window(state, {
            { start_row = 2, end_row = 3 },
        })

        local marks = vim.api.nvim_buf_get_extmarks(bufnr, state.ns, 0, -1, { details = true })

        assert.are.equal(1, #marks)
        assert.are.equal('', marks[1][4].conceal_lines)
        assert.are.equal(1, marks[1][2])
        assert.are.equal(2, marks[1][4].end_row)
        assert.are.same({ wins = { winid } }, vim.api.nvim__ns_get(state.ns))
        assert.are.same({
            { start_row = 2, end_row = 3 },
        }, render_provider.debug_window(state.winid).hidden_ranges)

        render_provider.clear_window(state)
        vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('keeps conceal marks local to each window when a buffer is shared', function()
        local bufnr = vim.api.nvim_create_buf(false, true)
        local top = vim.api.nvim_get_current_win()

        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'one', 'two', 'three', 'four', 'five' })
        vim.api.nvim_win_set_buf(top, bufnr)
        vim.cmd('belowright split')
        local bottom = vim.api.nvim_get_current_win()
        vim.api.nvim_win_set_buf(bottom, bufnr)

        local top_state = state_for(top, bufnr, 'shared.top')
        local bottom_state = state_for(bottom, bufnr, 'shared.bottom')

        render_provider.update_window(top_state, {
            { start_row = 2, end_row = 2 },
        })
        render_provider.update_window(bottom_state, {
            { start_row = 4, end_row = 4 },
        })

        assert.are.equal(1, #vim.api.nvim_buf_get_extmarks(bufnr, top_state.ns, 0, -1, {}))
        assert.are.equal(1, #vim.api.nvim_buf_get_extmarks(bufnr, bottom_state.ns, 0, -1, {}))
        assert.are.same({ wins = { top } }, vim.api.nvim__ns_get(top_state.ns))
        assert.are.same({ wins = { bottom } }, vim.api.nvim__ns_get(bottom_state.ns))

        render_provider.clear_window_marks(top_state)

        assert.are.same({}, vim.api.nvim_buf_get_extmarks(bufnr, top_state.ns, 0, -1, {}))
        assert.are.equal(1, #vim.api.nvim_buf_get_extmarks(bufnr, bottom_state.ns, 0, -1, {}))

        render_provider.clear_window(top_state)
        render_provider.clear_window(bottom_state)
        vim.api.nvim_win_close(bottom, true)
        vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('clears provider state tracked by window state', function()
        local bufnr = vim.api.nvim_create_buf(false, true)
        local winid = vim.api.nvim_get_current_win()
        local state = state_for(winid, bufnr, 'state-clear')

        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'one', 'two', 'three' })
        render_provider.update_window(state, {
            { start_row = 1, end_row = 1 },
        })
        render_apply.clear_state(state)

        assert.are.same({}, vim.api.nvim_buf_get_extmarks(bufnr, state.ns, 0, -1, {}))
        assert.is_nil(render_provider.debug_window(winid))

        vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('leaves the row after a hidden range visible on screen', function()
        local bufnr = vim.api.nvim_create_buf(false, true)
        local previous_bufnr = vim.api.nvim_get_current_buf()
        local previous_conceallevel = vim.wo.conceallevel
        local winid = vim.api.nvim_get_current_win()
        local state = state_for(winid, bufnr, 'row-after-range')

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

    it('keeps direct conceal decisions local to the rendering window', function()
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

        local top_state = state_for(top, bufnr, 'screen.top')
        local bottom_state = state_for(bottom, bufnr, 'screen.bottom')

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
