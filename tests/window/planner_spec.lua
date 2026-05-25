local planner = require('marginalia.window.planner')

describe('marginalia.window.planner', function()
    it('projects from captured window state and previous cursor state', function()
        local projection = planner.project({
            snapshot = {
                cursor_row = 144,
                line_count = 200,
                winheight = 40,
                raw_view = { topline = 142 },
                native_winline = 4,
                wrap = false,
            },
            state = {
                cursor = {
                    row = 145,
                    physical_row = 4,
                },
                viewport = {
                    logical_topline = 145,
                },
            },
            context_frames = {
                { row = 1, type = 'outer' },
                { row = 9, type = 'middle' },
                { row = 91, type = 'inner' },
            },
            event = 'CursorMoved',
        })

        assert.are.equal('linewise_cursor_motion', projection.reason)
        assert.are.equal(3, projection.cursor_physical_row)
        assert.are.same({ 9, 91 }, projection.context_rows)
        assert.are.equal(2, #projection.selected_candidates)
        assert.are.equal(9, projection.selected_candidates[1].source_row)
        assert.are.equal(91, projection.selected_candidates[2].source_row)
        assert.are.equal(2, #projection.selected_frames)
        assert.are.equal(9, projection.selected_frames[1].row)
        assert.are.equal(91, projection.selected_frames[2].row)
        assert.are.equal(144, projection.virtual_viewport.topline)
    end)

    it('threads captured wrap state into viewport projection', function()
        local projection = planner.project({
            snapshot = {
                cursor_row = 51,
                line_count = 100,
                winheight = 20,
                raw_view = { topline = 41 },
                native_winline = 12,
                wrap = true,
            },
            state = {
                cursor = {
                    row = 50,
                    physical_row = 4,
                },
            },
            event = 'CursorMoved',
        })

        assert.are.equal(12, projection.cursor_physical_row)
    end)

    it('keeps user and effective scrolloff separate', function()
        local projection = planner.project({
            snapshot = {
                cursor_row = 20,
                line_count = 100,
                winheight = 20,
                raw_view = { topline = 10 },
                native_winline = 11,
                wrap = false,
                window_scrolloff = 0,
            },
            scrolloff = 5,
        })

        assert.are.same({
            user = 0,
            effective = 5,
        }, projection.scrolloff)
    end)

    it('threads logical mouse scroll deltas into viewport projection', function()
        local projection = planner.project({
            snapshot = {
                cursor_row = 224,
                line_count = 320,
                winheight = 81,
                raw_view = { topline = 1 },
                native_winline = 7,
                wrap = true,
                window_scrolloff = 0,
            },
            state = {
                cursor = {
                    row = 224,
                    physical_row = 6,
                    native_physical_row = 6,
                },
                viewport = {
                    logical_topline = 221,
                },
            },
            context_frames = {
                { row = 1, type = 'outer' },
                { row = 9, type = 'middle' },
                { row = 222, type = 'inner' },
            },
            event = 'MouseScrolled',
            logical_scroll_delta = -3,
        })

        assert.are.equal('logical_scroll', projection.reason)
        assert.are.same({ 1, 9 }, projection.context_rows)
        assert.are.equal(218, projection.virtual_viewport.topline)
    end)
end)
