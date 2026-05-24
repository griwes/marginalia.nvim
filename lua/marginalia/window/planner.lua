local context_normalize = require('marginalia.context.normalize')
local viewport = require('marginalia.viewport')

local M = {}

---@param opts { snapshot: marginalia.WindowSnapshot, state?: marginalia.WindowState|table, context_frames?: marginalia.ContextFrame[], scrolloff?: integer, event?: string }
---@return marginalia.ViewportProjection
function M.project(opts)
    local snapshot = opts.snapshot
    local state = opts.state or {}

    return viewport.project({
        cursor_row = snapshot.cursor_row,
        line_count = snapshot.line_count,
        winheight = snapshot.winheight,
        raw_topline = snapshot.raw_view.topline,
        current_physical_row = snapshot.native_winline,
        wrap = snapshot.wrap,
        prior_cursor_row = state.cursor and state.cursor.row or nil,
        prior_physical_row = state.cursor and state.cursor.physical_row or nil,
        prior_native_physical_row = state.cursor and state.cursor.native_physical_row or nil,
        prior_virtual_topline = state.viewport and state.viewport.logical_topline or nil,
        user_scrolloff = snapshot.window_scrolloff,
        effective_scrolloff = opts.scrolloff or 0,
        event = opts.event,
        candidates = context_normalize.candidates(opts.context_frames or {}, snapshot.cursor_row),
    })
end

return M
