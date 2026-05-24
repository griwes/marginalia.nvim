local debug_snapshot = require('marginalia.window.debug')
local window_state = require('marginalia.window.state')

describe('marginalia.window.debug', function()
    it('returns structured context, viewport, render, and transaction state', function()
        local winid = vim.api.nvim_get_current_win()
        local state = assert(window_state.ensure(winid))

        state.cursor.row = 12
        state.semantic.context = {
            frames = {
                { row = 1, type = 'outer' },
                { row = 9, type = 'inner' },
            },
        }
        state.viewport.applied_projection = {
            context_rows = { 1, 9 },
        }
        state.render.artifact = {
            visible_rows = { 1, 9, 12 },
            hidden_ranges = {
                { start_row = 2, end_row = 8 },
            },
        }
        state.transaction.epoch = 3

        local snapshot = assert(debug_snapshot.snapshot(winid))

        assert.are.equal(winid, snapshot.winid)
        assert.are.same(state.semantic.context.frames, snapshot.context.result.frames)
        assert.are.equal(2, #snapshot.context.candidates)
        assert.are.same({ 1, 9 }, snapshot.viewport.projection.context_rows)
        assert.are.same({ 1, 9, 12 }, snapshot.render.artifact.visible_rows)
        assert.are.equal(3, snapshot.transaction.epoch)

        snapshot.context.result.frames[1].row = 99

        assert.are.equal(1, state.semantic.context.frames[1].row)

        window_state.remove(winid)
    end)

    it('returns nil for unattached windows', function()
        assert.is_nil(debug_snapshot.snapshot())
    end)
end)
