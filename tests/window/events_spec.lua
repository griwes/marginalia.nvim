describe('marginalia.window.events', function()
    local events = require('marginalia.window.events')
    local window_state = require('marginalia.window.state')

    after_each(function()
        events._reset_for_tests()
        window_state.remove(vim.api.nvim_get_current_win())
    end)

    it('schedules cursor movement refreshes outside the motion event', function()
        local winid = vim.api.nvim_get_current_win()
        local calls = {}

        window_state.ensure(winid)
        events._set_refresh_for_tests(function(call_winid, opts)
            calls[#calls + 1] = {
                winid = call_winid,
                opts = opts,
            }
        end)

        events.enqueue(winid, { _event = 'CursorMoved', marker = 1 })

        assert.are.equal(0, #calls)

        vim.wait(100, function()
            return #calls == 1
        end)

        assert.are.equal(1, #calls)
        assert.are.equal(winid, calls[1].winid)
        assert.are.equal(1, calls[1].opts.marker)
        assert.are.equal('CursorMoved', calls[1].opts._event)
        assert.is_true(calls[1].opts._events.CursorMoved)
    end)

    it('prioritizes pending cursor movement over scroll noise', function()
        local winid = vim.api.nvim_get_current_win()
        local calls = {}

        window_state.ensure(winid)
        events._set_refresh_for_tests(function(call_winid, opts)
            calls[#calls + 1] = {
                winid = call_winid,
                opts = opts,
            }
        end)

        events.enqueue(winid, { _event = 'WinScrolled', marker = 1 })
        events.enqueue(winid, { _event = 'CursorMoved', marker = 2 })

        assert.are.equal(0, #calls)

        vim.wait(100, function()
            return #calls == 1
        end)

        assert.are.equal(1, #calls)
        assert.are.equal(winid, calls[1].winid)
        assert.are.equal(2, calls[1].opts.marker)
        assert.are.equal('CursorMoved', calls[1].opts._event)
        assert.is_true(calls[1].opts._events.CursorMoved)
        assert.is_true(calls[1].opts._events.WinScrolled)
    end)

    it('coalesces queued non-cursor refreshes per window', function()
        local winid = vim.api.nvim_get_current_win()
        local calls = {}

        window_state.ensure(winid)
        events._set_refresh_for_tests(function(call_winid, opts)
            calls[#calls + 1] = {
                winid = call_winid,
                opts = opts,
            }
        end)

        events.enqueue(winid, { _event = 'WinScrolled', marker = 1 })
        events.enqueue(winid, { _event = 'WinScrolled', marker = 2 })

        vim.wait(100, function()
            return #calls == 1
        end)

        assert.are.equal(1, #calls)
        assert.are.equal(winid, calls[1].winid)
        assert.are.equal(2, calls[1].opts.marker)
        assert.are.equal('WinScrolled', calls[1].opts._event)
        assert.is_true(calls[1].opts._events.WinScrolled)
    end)

    it('drops queued work for unattached windows', function()
        local winid = vim.api.nvim_get_current_win()
        local calls = 0

        events._set_refresh_for_tests(function()
            calls = calls + 1
        end)

        events.enqueue(winid, { _event = 'CursorMoved' })

        vim.wait(100, function()
            return calls > 0
        end)

        assert.are.equal(0, calls)
    end)
end)
