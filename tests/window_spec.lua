local render_apply = require('marginalia.render.apply')
local render_provider = require('marginalia.render.provider')
local window = require('marginalia.window')

describe('marginalia.window', function()
    local previous_conceallevel
    local previous_scrolloff
    local previous_global_scrolloff
    local previous_lines
    local previous_restore_target_topline

    local function line_buffer(count)
        local bufnr = vim.api.nvim_create_buf(false, true)
        local lines = {}

        for row = 1, count do
            lines[row] = 'line ' .. row
        end

        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
        return bufnr
    end

    before_each(function()
        previous_conceallevel = vim.wo.conceallevel
        previous_scrolloff = vim.wo.scrolloff
        previous_global_scrolloff = vim.o.scrolloff
        previous_lines = vim.o.lines
        previous_restore_target_topline = render_apply.restore_target_topline
        vim.wo.conceallevel = 0
        vim.wo.scrolloff = 0
        vim.o.scrolloff = 0
    end)

    after_each(function()
        window.detach()
        vim.wo.conceallevel = previous_conceallevel
        vim.wo.scrolloff = previous_scrolloff
        vim.o.scrolloff = previous_global_scrolloff
        vim.o.lines = previous_lines
        render_apply.restore_target_topline = previous_restore_target_topline
    end)

    it('sets and restores conceallevel around a non-empty projection', function()
        local bufnr = line_buffer(40)

        vim.api.nvim_win_set_buf(0, bufnr)
        vim.api.nvim_win_set_height(0, 8)
        vim.api.nvim_win_set_cursor(0, { 12, 0 })
        vim.fn.winrestview({ topline = 10 })

        assert.is_true(window.attach(0, {
            render = {
                conceallevel = 2,
            },
            frames = {
                { row = 1 },
            },
        }))
        assert.are.equal(2, vim.wo.conceallevel)

        window.detach()

        assert.are.equal(0, vim.wo.conceallevel)
        vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('leaves conceallevel alone when no context is available', function()
        assert.is_true(window.attach(0, {
            render = {
                conceallevel = 2,
            },
            context_result = { frames = {}, reason = 'no_parser' },
        }))
        assert.are.equal(0, vim.wo.conceallevel)
    end)

    it('does not pin context rows that are already naturally visible', function()
        local bufnr = line_buffer(40)
        local restore_calls = 0

        render_apply.restore_target_topline = function(...)
            restore_calls = restore_calls + 1
            return previous_restore_target_topline(...)
        end

        vim.api.nvim_win_set_buf(0, bufnr)
        vim.api.nvim_win_set_height(0, 12)
        vim.api.nvim_win_set_cursor(0, { 12, 0 })
        vim.fn.winrestview({ topline = 1 })

        window.attach(0, {
            viewport = {
                respect_scrolloff = false,
            },
            frames = {
                { row = 1 },
                { row = 3 },
            },
        })

        local state = window.state()

        assert.are.equal(1, state.viewport.applied_projection.actual_viewport.topline)
        assert.are.same({}, state.render.plan.hidden_ranges)
        assert.are.equal(1, vim.fn.line('w0'))
        assert.are.equal(0, restore_calls)

        vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('pins only context rows above the projected virtual body viewport', function()
        local bufnr = line_buffer(60)

        vim.api.nvim_win_set_buf(0, bufnr)
        vim.api.nvim_win_set_height(0, 20)
        vim.api.nvim_win_set_cursor(0, { 20, 0 })
        vim.fn.winrestview({ topline = 10 })

        window.attach(0, {
            viewport = {
                respect_scrolloff = false,
            },
            frames = {
                { row = 1 },
                { row = 10 },
            },
        })

        local state = window.state()

        assert.are.same({ 1, 10 }, state.viewport.applied_projection.context_rows)
        assert.are.equal(12, state.viewport.applied_projection.virtual_viewport.topline)
        assert.are.equal(1, state.viewport.applied_projection.actual_viewport.topline)
        assert.are.same({
            { start_row = 2, end_row = 9 },
            { start_row = 11, end_row = 11 },
        }, state.render.plan.hidden_ranges)

        vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('pins context when native linewise scrolling starts', function()
        local bufnr = line_buffer(60)

        vim.api.nvim_win_set_buf(0, bufnr)
        vim.api.nvim_win_set_height(0, 18)
        vim.wo.scrolloff = 0
        vim.api.nvim_win_set_cursor(0, { 18, 0 })
        vim.fn.winrestview({ topline = 1 })

        local opts = {
            viewport = {
                respect_scrolloff = false,
            },
            frames = {
                { row = 1, type = 'section' },
                { row = 3, type = 'section' },
            },
        }

        window.attach(0, opts)
        vim.cmd('normal! j')
        window.refresh(0, vim.tbl_extend('force', opts, { _event = 'CursorMoved' }))

        assert.are.equal(19, vim.api.nvim_win_get_cursor(0)[1])
        assert.are.same({ 1 }, window.state().viewport.applied_projection.context_rows)
        assert.are.same({
            { start_row = 2, end_row = 2 },
        }, window.state().render.plan.hidden_ranges)
        assert.are.equal(18, vim.fn.winline())

        vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('turns blocked native scroll down into cursor motion below pinned context', function()
        local bufnr = line_buffer(120)

        vim.api.nvim_win_set_buf(0, bufnr)
        vim.api.nvim_win_set_height(0, 81)
        vim.wo.scrolloff = 0
        vim.api.nvim_win_set_cursor(0, { 7, 0 })
        vim.fn.winrestview({ topline = 5 })

        local opts = {
            viewport = {
                respect_scrolloff = false,
            },
            frames = {
                { row = 1, type = 'section' },
                { row = 3, type = 'section' },
            },
        }

        window.attach(0, opts)

        assert.are.equal(7, vim.api.nvim_win_get_cursor(0)[1])
        assert.are.same({ 1, 3 }, window.state().viewport.applied_projection.context_rows)
        assert.are.equal(3, window.state().cursor.physical_row)

        vim.fn.winrestview({ topline = 6 })
        window.refresh(
            0,
            vim.tbl_extend('force', opts, {
                _event = 'WinScrolled',
                _native_scroll_delta = 1,
            })
        )

        assert.are.equal(8, vim.api.nvim_win_get_cursor(0)[1])
        assert.are.same({ 1, 3 }, window.state().viewport.applied_projection.context_rows)
        assert.are.same({
            { start_row = 2, end_row = 2 },
            { start_row = 4, end_row = 7 },
        }, window.state().render.plan.hidden_ranges)
        assert.are.equal(3, window.state().cursor.physical_row)
        assert.are.equal(1, vim.fn.line('w0'))

        vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('keeps newly selected context visible when native scroll needs no conceal gap', function()
        local bufnr = line_buffer(120)

        vim.api.nvim_win_set_buf(0, bufnr)
        vim.api.nvim_win_set_height(0, 81)
        vim.wo.scrolloff = 0
        vim.api.nvim_win_set_cursor(0, { 8, 0 })
        vim.fn.winrestview({ topline = 1 })

        local opts = {
            viewport = {
                respect_scrolloff = false,
            },
            frames = {
                { row = 1, type = 'section' },
                { row = 3, type = 'section' },
            },
        }

        window.attach(0, opts)

        assert.are.same({}, window.state().viewport.applied_projection.context_rows)
        assert.are.equal(1, vim.fn.line('w0'))

        vim.fn.winrestview({ topline = 2 })
        window.refresh(
            0,
            vim.tbl_extend('force', opts, {
                _event = 'WinScrolled',
                _native_scroll_delta = 1,
            })
        )

        assert.are.equal(8, vim.api.nvim_win_get_cursor(0)[1])
        assert.are.same({ 1 }, window.state().viewport.applied_projection.context_rows)
        assert.are.same({}, window.state().render.plan.hidden_ranges)
        assert.are.equal(2, window.state().viewport.applied_projection.virtual_viewport.topline)
        assert.are.equal(1, vim.fn.line('w0'))

        vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('recovers page-up cursor motion that native scrolling skipped across concealed rows', function()
        local bufnr = line_buffer(400)

        vim.o.lines = 100
        vim.api.nvim_win_set_buf(0, bufnr)
        vim.api.nvim_win_set_height(0, 81)
        vim.wo.scrolloff = 0
        local opts = {
            viewport = {
                respect_scrolloff = false,
            },
            frames = {
                { row = 1, type = 'section' },
                { row = 9, type = 'section' },
            },
        }

        vim.api.nvim_win_set_cursor(0, { 327, 0 })
        vim.fn.winrestview({ topline = 249 })
        window.attach(0, opts)

        vim.api.nvim_win_set_cursor(0, { 287, 0 })
        vim.fn.winrestview({ topline = 1 })
        window.refresh(0, vim.tbl_extend('force', opts, { _event = 'CursorMoved' }))

        assert.are.same({ 1, 9 }, window.state().viewport.applied_projection.context_rows)
        assert.are.equal(287, window.state().cursor.row)
        assert.are.equal(39, window.state().cursor.physical_row)

        vim.api.nvim_win_set_cursor(0, { 1, 0 })
        vim.fn.winrestview({ topline = 1 })
        window.refresh(0, vim.tbl_extend('force', opts, { _event = 'CursorMoved' }))

        assert.are.equal(249, vim.api.nvim_win_get_cursor(0)[1])
        assert.are.same({ 1, 9 }, window.state().viewport.applied_projection.context_rows)
        assert.are.equal(39, window.state().cursor.physical_row)
        assert.are.equal(213, window.state().viewport.applied_projection.virtual_viewport.topline)
        assert.are.equal(1, vim.fn.line('w0'))

        vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('trusts native jumps to the top instead of recovering across concealed rows', function()
        local bufnr = line_buffer(400)

        vim.o.lines = 100
        vim.api.nvim_win_set_buf(0, bufnr)
        vim.api.nvim_win_set_height(0, 81)
        vim.wo.scrolloff = 0
        local opts = {
            viewport = {
                respect_scrolloff = false,
            },
            frames = {
                { row = 1, type = 'section' },
                { row = 9, type = 'section' },
            },
        }

        vim.api.nvim_win_set_cursor(0, { 327, 0 })
        vim.fn.winrestview({ topline = 249 })
        window.attach(0, opts)

        local window_snapshot = require('marginalia.window.snapshot')
        local original_capture = window_snapshot.capture
        local prior_jumplist = assert(window.state().cursor.jumplist)

        vim.api.nvim_win_set_cursor(0, { 1, 0 })
        vim.fn.winrestview({ topline = 1 })

        window_snapshot.capture = function(winid)
            local snapshot = original_capture(winid)
            snapshot.jumplist = {
                index = prior_jumplist.index,
                length = prior_jumplist.length,
                current = {
                    bufnr = bufnr,
                    lnum = 327,
                    col = 0,
                    coladd = 0,
                },
            }
            return snapshot
        end

        window.refresh(0, vim.tbl_extend('force', opts, { _event = 'CursorMoved' }))
        window_snapshot.capture = original_capture

        assert.are.equal(1, vim.api.nvim_win_get_cursor(0)[1])
        assert.are.same({}, window.state().viewport.applied_projection.context_rows)
        assert.are.same({}, window.state().render.plan.hidden_ranges)
        assert.are.equal(1, vim.fn.line('w0'))

        vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('records the settled viewport after conceal redraws', function()
        local bufnr = line_buffer(120)

        vim.api.nvim_win_set_buf(0, bufnr)
        vim.api.nvim_win_set_height(0, 78)
        vim.wo.scrolloff = 0
        vim.api.nvim_win_set_cursor(0, { 78, 0 })
        vim.fn.winrestview({ topline = 3 })

        local opts = {
            viewport = {
                respect_scrolloff = false,
            },
            frames = {
                { row = 1, type = 'section' },
                { row = 9, type = 'section' },
                { row = 75, type = 'section' },
            },
        }

        window.attach(0, opts)
        vim.cmd('normal! j')
        window.refresh(0, vim.tbl_extend('force', opts, { _event = 'CursorMoved' }))
        vim.cmd('redraw')

        local state = window.state()
        local settled_view = vim.fn.winsaveview()

        assert.are.equal(settled_view.topline, state.viewport.raw_topline)
        assert.are.equal(settled_view.topline, state.transaction.expected_scroll_echo.raw_topline)

        vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('reasserts the target viewport when conceal redraw echoes land on the previous topline', function()
        local bufnr = line_buffer(120)

        vim.api.nvim_win_set_buf(0, bufnr)
        vim.api.nvim_win_set_height(0, 78)
        vim.wo.scrolloff = 0
        vim.api.nvim_win_set_cursor(0, { 77, 0 })
        vim.fn.winrestview({ topline = 2 })

        local opts = {
            viewport = {
                respect_scrolloff = false,
            },
            frames = {
                { row = 1, type = 'section' },
            },
        }

        window.attach(0, opts)

        local state = window.state()
        local target_topline = state.viewport.applied_projection.actual_viewport.topline

        assert.are.equal(1, target_topline)
        assert.are.equal(target_topline, vim.fn.line('w0'))

        vim.fn.winrestview({ topline = 2 })

        assert.are.equal(2, vim.fn.line('w0'))
        assert.is_true(state.transaction.expected_scroll_echo.raw_toplines[2])

        window.refresh(0, vim.tbl_extend('force', opts, { _event = 'WinScrolled' }))

        state = window.state()

        assert.are.equal(target_topline, state.viewport.raw_topline)
        assert.are.equal(target_topline, vim.fn.line('w0'))
        assert.are.equal(state.transaction.epoch, state.transaction.scroll_echo_reasserted_epoch)

        vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('reasserts the target viewport when scroll drift is observed during an option echo', function()
        local bufnr = line_buffer(120)

        vim.api.nvim_win_set_buf(0, bufnr)
        vim.api.nvim_win_set_height(0, 78)
        vim.wo.scrolloff = 0
        vim.api.nvim_win_set_cursor(0, { 77, 0 })
        vim.fn.winrestview({ topline = 2 })

        local opts = {
            viewport = {
                respect_scrolloff = false,
            },
            frames = {
                { row = 1, type = 'section' },
            },
        }

        window.attach(0, opts)

        local state = window.state()
        local target_topline = state.viewport.applied_projection.actual_viewport.topline

        assert.are.equal(1, target_topline)
        assert.is_not_nil(state.transaction.expected_option_echo)

        vim.fn.winrestview({ topline = 2 })
        window.refresh(0, vim.tbl_extend('force', opts, { _event = 'OptionSet:scrolloff' }))

        state = window.state()

        assert.are.equal(target_topline, state.viewport.raw_topline)
        assert.are.equal(target_topline, vim.fn.line('w0'))
        assert.are.equal(state.transaction.epoch, state.transaction.scroll_echo_reasserted_epoch)

        vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('records user and effective scrolloff separately after render suppression', function()
        local bufnr = line_buffer(80)

        vim.api.nvim_win_set_buf(0, bufnr)
        vim.api.nvim_win_set_height(0, 20)
        vim.wo.scrolloff = 5
        vim.api.nvim_win_set_cursor(0, { 40, 0 })
        vim.fn.winrestview({ topline = 31 })

        window.attach(0, {
            frames = {
                { row = 1 },
                { row = 20 },
            },
        })

        assert.are.same({
            user = 5,
            effective = 5,
        }, window.state().viewport.applied_projection.scrolloff)
        assert.are.equal(0, vim.wo.scrolloff)

        vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('marks target-topline scrolloff echoes after initial suppression was consumed', function()
        local bufnr = line_buffer(120)

        vim.api.nvim_win_set_buf(0, bufnr)
        vim.api.nvim_win_set_height(0, 40)
        vim.wo.scrolloff = 0
        vim.api.nvim_win_set_cursor(0, { 82, 0 })
        vim.fn.winrestview({ topline = 11 })

        local opts = {
            viewport = {
                respect_scrolloff = false,
            },
            frames = {
                { row = 1, type = 'section' },
                { row = 9, type = 'section' },
                { row = 79, type = 'section' },
            },
        }

        window.attach(0, opts)

        window.refresh(0, {
            _event = 'OptionSet:scrolloff',
            viewport = {
                respect_scrolloff = false,
            },
            context_result = { frames = {}, reason = 'internal_scrolloff_echo' },
        })

        assert.is_nil(window.state().transaction.expected_option_echo)

        window.refresh(0, vim.tbl_extend('force', opts, { _event = 'CursorMoved' }))

        assert.are.same({ scrolloff = true }, window.state().transaction.expected_option_echo.options)

        vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('ignores WinScrolled echoes caused by its own redraw work', function()
        local bufnr = line_buffer(120)

        vim.api.nvim_win_set_buf(0, bufnr)
        vim.api.nvim_win_set_height(0, 40)
        vim.api.nvim_win_set_cursor(0, { 78, 0 })
        vim.wo.scrolloff = 0
        vim.fn.winrestview({ topline = 59 })

        local opts = {
            viewport = {
                respect_scrolloff = false,
            },
            frames = {
                { row = 1, type = 'section' },
                { row = 9, type = 'section' },
                { row = 41, type = 'section' },
            },
        }

        window.attach(0, opts)
        local expected = vim.deepcopy(window.state().render.plan.hidden_ranges)

        window.refresh(0, {
            _event = 'WinScrolled',
            viewport = {
                respect_scrolloff = false,
            },
            context_result = { frames = {}, reason = 'transient_redraw_probe' },
        })

        assert.are.same(expected, window.state().render.plan.hidden_ranges)

        vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('restores prior window options before rebinding to another buffer', function()
        local first_bufnr = line_buffer(40)
        local second_bufnr = line_buffer(40)
        local original_bufnr = vim.api.nvim_get_current_buf()
        local original_height = vim.api.nvim_win_get_height(0)
        local opts = {
            viewport = { respect_scrolloff = false },
            frames = { { row = 1 } },
        }

        vim.api.nvim_win_set_buf(0, first_bufnr)
        vim.api.nvim_win_set_height(0, 8)
        vim.wo.conceallevel = 0
        vim.wo.scrolloff = 5
        vim.api.nvim_win_set_cursor(0, { 12, 0 })
        vim.fn.winrestview({ topline = 10 })
        window.attach(0, opts)

        assert.are.equal(2, vim.wo.conceallevel)
        assert.are.equal(0, vim.wo.scrolloff)

        vim.api.nvim_win_set_buf(0, second_bufnr)
        vim.api.nvim_win_set_cursor(0, { 12, 0 })
        vim.fn.winrestview({ topline = 10 })
        window.refresh(0, opts)
        window.detach()

        assert.are.equal(0, vim.wo.conceallevel)
        assert.are.equal(5, vim.wo.scrolloff)

        vim.api.nvim_win_set_buf(0, original_bufnr)
        vim.api.nvim_win_set_height(0, original_height)
        vim.api.nvim_buf_delete(first_bufnr, { force = true })
        vim.api.nvim_buf_delete(second_bufnr, { force = true })
    end)

    it('leaves window options and view untouched when namespace scoping is unavailable', function()
        local bufnr = line_buffer(40)
        local original_bufnr = vim.api.nvim_get_current_buf()
        local original_ns_set = vim.api.nvim__ns_set
        local original_notify_once = vim.notify_once
        local original_height = vim.api.nvim_win_get_height(0)
        local plan

        vim.api.nvim_win_set_buf(0, bufnr)
        vim.api.nvim_win_set_height(0, 8)
        vim.wo.conceallevel = 0
        vim.wo.scrolloff = 4
        vim.api.nvim_win_set_cursor(0, { 12, 0 })
        vim.fn.winrestview({ topline = 10 })
        local original_topline = vim.fn.line('w0')

        vim.api.nvim__ns_set = nil
        vim.notify_once = function() end

        local ok, err = pcall(function()
            plan = window.attach(0, {
                viewport = { respect_scrolloff = false },
                frames = { { row = 1 } },
            }) and window.state().render.plan
        end)

        vim.api.nvim__ns_set = original_ns_set
        vim.notify_once = original_notify_once

        assert.is_true(ok, err)
        assert.is_not_nil(plan.render_error)
        assert.are.same({}, plan.hidden_ranges)
        assert.are.equal(0, vim.wo.conceallevel)
        assert.are.equal(4, vim.wo.scrolloff)
        assert.are.equal(original_topline, vim.fn.line('w0'))

        vim.api.nvim_win_set_buf(0, original_bufnr)
        vim.api.nvim_win_set_height(0, original_height)
        vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('clears marks when no context is available', function()
        local bufnr = vim.api.nvim_create_buf(false, true)

        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'one', 'two', 'three' })
        vim.api.nvim_win_set_buf(0, bufnr)
        vim.api.nvim_win_set_cursor(0, { 3, 0 })

        window.attach(0, {
            frames = {
                { row = 1 },
            },
        })
        window.refresh(0, { context_result = { frames = {}, reason = 'no_parser' } })

        local state = window.state()

        assert.are.same({}, vim.api.nvim_buf_get_extmarks(bufnr, state.ns, 0, -1, {}))
        assert.are.same({}, vim.api.nvim_buf_get_extmarks(bufnr, render_provider.namespace(), 0, -1, {}))
        assert.is_nil(render_provider.debug_window(state.winid))

        vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
end)
