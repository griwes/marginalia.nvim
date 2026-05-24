local context_normalize = require('marginalia.context.normalize')
local viewport = require('marginalia.viewport')

describe('marginalia.viewport', function()
    it('allocates context rows by preserving innermost candidates first', function()
        local candidates = context_normalize.candidates({
            { row = 1, type = 'outer' },
            { row = 9, type = 'middle' },
            { row = 91, type = 'inner' },
        }, 143)

        local rows = viewport.allocate_context_rows(candidates, 2)

        assert.are.same({ 9, 91 }, rows)
    end)

    it('shrinks context to preserve adjacent physical cursor motion', function()
        local candidates = context_normalize.candidates({
            { row = 1, type = 'outer' },
            { row = 9, type = 'middle' },
            { row = 91, type = 'inner' },
        }, 144)

        local projection = viewport.project({
            cursor_row = 144,
            line_count = 200,
            winheight = 40,
            raw_topline = 142,
            current_physical_row = 4,
            prior_cursor_row = 145,
            prior_physical_row = 4,
            scrolloff = 0,
            candidates = candidates,
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

    it('truncates projected selected frames to the selected physical rows', function()
        local candidates = context_normalize.candidates({
            {
                range = {
                    start_row = 10,
                    start_col = 0,
                    end_row = 14,
                    end_col = 0,
                },
                type = 'multiline',
            },
        }, 20)

        local projection = viewport.project({
            cursor_row = 20,
            line_count = 100,
            winheight = 20,
            raw_topline = 1,
            current_physical_row = 3,
            scrolloff = 0,
            candidates = candidates,
        })

        assert.are.same({ 10, 11 }, projection.context_rows)
        assert.are.equal(1, #projection.selected_frames)
        assert.are.same({
            start_row = 10,
            start_col = 0,
            end_row = 12,
            end_col = 0,
        }, projection.selected_frames[1].range)
    end)

    it('materializes displayed frames from selected physical rows', function()
        local frames = {
            {
                type = 'function_definition',
                range = {
                    start_row = 10,
                    start_col = 0,
                    end_row = 14,
                    end_col = 0,
                },
            },
            { row = 20, type = 'inner' },
        }

        assert.are.same({
            {
                type = 'function_definition',
                range = {
                    start_row = 10,
                    start_col = 0,
                    end_row = 12,
                    end_col = 0,
                },
            },
            { row = 20, type = 'inner' },
        }, viewport.displayed_frames_from_rows(frames, { 10, 11, 20 }))
    end)

    it('limits context rows by available physical rows above the cursor', function()
        local candidates = context_normalize.candidates({
            { row = 1, type = 'outer' },
            { row = 9, type = 'middle' },
            { row = 91, type = 'inner' },
        }, 145)

        local projection = viewport.project({
            cursor_row = 145,
            line_count = 200,
            winheight = 40,
            raw_topline = 142,
            current_physical_row = 4,
            scrolloff = 0,
            candidates = candidates,
        })

        assert.are.same({ 1, 9, 91 }, projection.context_rows)
        assert.are.equal(4, projection.cursor_physical_row)
        assert.are.equal(145, projection.virtual_viewport.topline)
    end)

    it('does not pin context rows that are already in the virtual body viewport', function()
        local candidates = context_normalize.candidates({
            { row = 10, type = 'visible_context' },
        }, 20)

        local projection = viewport.project({
            cursor_row = 20,
            line_count = 100,
            winheight = 20,
            raw_topline = 10,
            current_physical_row = 11,
            scrolloff = 0,
            candidates = candidates,
        })

        assert.are.same({}, projection.context_rows)
        assert.are.equal(10, projection.virtual_viewport.topline)
        assert.are.equal(10, projection.actual_viewport.topline)
        assert.are.same({ 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20 }, projection.visible_rows)
    end)

    it('promotes newly displaced context rows after earlier pins shrink the virtual body viewport', function()
        local candidates = context_normalize.candidates({
            { row = 1, type = 'outer' },
            { row = 10, type = 'displaced_context' },
        }, 20)

        local projection = viewport.project({
            cursor_row = 20,
            line_count = 100,
            winheight = 20,
            raw_topline = 10,
            current_physical_row = 11,
            scrolloff = 0,
            candidates = candidates,
        })

        assert.are.same({ 1, 10 }, projection.context_rows)
        assert.are.equal(12, projection.virtual_viewport.topline)
        assert.are.equal(1, projection.actual_viewport.topline)
        assert.are.same({ 1, 10, 12, 13, 14, 15, 16, 17, 18, 19, 20 }, projection.visible_rows)
    end)

    it('respects scrolloff near the top of the buffer', function()
        local candidates = context_normalize.candidates({
            { row = 1, type = 'outer' },
        }, 2)

        local projection = viewport.project({
            cursor_row = 2,
            line_count = 100,
            winheight = 20,
            raw_topline = 1,
            current_physical_row = 2,
            scrolloff = 5,
            candidates = candidates,
        })

        assert.are.equal(2, projection.cursor_physical_row)
        assert.are.same({}, projection.context_rows)
        assert.are.equal(1, projection.virtual_viewport.topline)
    end)

    it('respects scrolloff in the middle of the buffer', function()
        local candidates = context_normalize.candidates({
            { row = 1, type = 'outer' },
            { row = 20, type = 'middle' },
            { row = 45, type = 'inner' },
        }, 50)

        local projection = viewport.project({
            cursor_row = 50,
            line_count = 100,
            winheight = 20,
            raw_topline = 41,
            current_physical_row = 10,
            scrolloff = 5,
            candidates = candidates,
        })

        assert.are.equal(10, projection.cursor_physical_row)
        assert.are.same({ 1, 20 }, projection.context_rows)
        assert.are.equal(43, projection.virtual_viewport.topline)
    end)

    it('respects scrolloff near the bottom of the buffer', function()
        local projection = viewport.project({
            cursor_row = 98,
            line_count = 100,
            winheight = 20,
            raw_topline = 81,
            current_physical_row = 18,
            scrolloff = 5,
            candidates = {},
        })

        assert.are.equal(18, projection.cursor_physical_row)
        assert.are.equal(81, projection.virtual_viewport.topline)
    end)

    it('shrinks context as the cursor approaches the top physical row', function()
        local candidates = context_normalize.candidates({
            { row = 1, type = 'outer' },
            { row = 9, type = 'middle' },
            { row = 91, type = 'inner' },
        }, 143)

        local projection = viewport.project({
            cursor_row = 143,
            line_count = 200,
            winheight = 40,
            raw_topline = 142,
            current_physical_row = 3,
            prior_cursor_row = 144,
            prior_physical_row = 3,
            scrolloff = 0,
            candidates = candidates,
            event = 'CursorMoved',
        })

        assert.are.equal(2, projection.cursor_physical_row)
        assert.are.same({ 91 }, projection.context_rows)
        assert.are.equal(143, projection.virtual_viewport.topline)
    end)

    it('uses prior native row as the base for adjacent motion deltas', function()
        local candidates = context_normalize.candidates({
            { row = 1, type = 'outer' },
        }, 4)

        local projection = viewport.project({
            cursor_row = 4,
            line_count = 100,
            winheight = 78,
            raw_topline = 1,
            current_physical_row = 4,
            prior_cursor_row = 3,
            prior_physical_row = 2,
            prior_native_physical_row = 3,
            scrolloff = 0,
            candidates = candidates,
            event = 'CursorMoved',
        })

        assert.are.equal('linewise_cursor_motion', projection.reason)
        assert.are.equal(4, projection.cursor_physical_row)
        assert.are.same({}, projection.context_rows)
        assert.are.same({ 1, 2, 3, 4 }, projection.visible_rows)
    end)

    it('does not spend native linewise scroll rows on context', function()
        local candidates = context_normalize.candidates({
            { row = 1, type = 'outer' },
            { row = 3, type = 'inner' },
        }, 4)

        local projection = viewport.project({
            cursor_row = 4,
            line_count = 20,
            winheight = 3,
            raw_topline = 2,
            current_physical_row = 3,
            prior_cursor_row = 3,
            prior_native_physical_row = 3,
            prior_virtual_topline = 1,
            scrolloff = 0,
            candidates = candidates,
            event = 'CursorMoved',
        })

        assert.are.equal('linewise_cursor_motion', projection.reason)
        assert.are.equal(3, projection.cursor_physical_row)
        assert.are.same({}, projection.context_rows)
        assert.are.equal(2, projection.virtual_viewport.topline)
        assert.are.same({ 2, 3, 4 }, projection.visible_rows)
    end)

    it('preserves semantic context change as the projection reason', function()
        local projection = viewport.project({
            cursor_row = 10,
            line_count = 100,
            winheight = 20,
            raw_topline = 1,
            current_physical_row = 10,
            event = 'semantic_context_changed',
        })

        assert.are.equal('semantic_context_changed', projection.reason)
    end)

    it('uses the native physical row for wrapped linewise movement', function()
        local projection = viewport.project({
            cursor_row = 51,
            line_count = 100,
            winheight = 20,
            raw_topline = 41,
            current_physical_row = 12,
            prior_cursor_row = 50,
            prior_physical_row = 4,
            event = 'CursorMoved',
            wrap = true,
        })

        assert.are.equal('linewise_cursor_motion', projection.reason)
        assert.are.equal(12, projection.cursor_physical_row)
    end)
end)
