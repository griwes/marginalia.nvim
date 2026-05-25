local context_normalize = require('marginalia.context.normalize')
local viewport = require('marginalia.viewport')

local M = {}

---@param snapshot marginalia.WindowSnapshot
---@return fun(row: integer): integer
local function row_height_provider(snapshot)
    local cache = {}

    return function(row)
        if type(row) ~= 'number' or row < 1 or row > snapshot.line_count then
            return 1
        end

        local cached = cache[row]

        if cached then
            return cached
        end

        if not vim.api.nvim_win_is_valid(snapshot.winid) or not vim.api.nvim_win_text_height then
            cache[row] = 1
            return 1
        end

        local ok, height = pcall(vim.api.nvim_win_text_height, snapshot.winid, {
            start_row = row - 1,
            end_row = row - 1,
        })

        local value = 1

        if ok and type(height) == 'table' and type(height.all) == 'number' and height.all > 0 then
            value = math.max(1, math.floor(height.all))
        end

        cache[row] = value
        return value
    end
end

---@param opts { snapshot: marginalia.WindowSnapshot, state?: marginalia.WindowState|table, context_frames?: marginalia.ContextFrame[], scrolloff?: integer, event?: string, logical_scroll_delta?: integer }
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
        logical_scroll_delta = opts.logical_scroll_delta,
        user_scrolloff = snapshot.window_scrolloff,
        effective_scrolloff = opts.scrolloff or 0,
        event = opts.event,
        candidates = context_normalize.candidates(opts.context_frames or {}, snapshot.cursor_row),
        row_height = row_height_provider(snapshot),
    })
end

return M
