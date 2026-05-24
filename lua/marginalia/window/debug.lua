local context_normalize = require('marginalia.context.normalize')
local render_provider = require('marginalia.render.provider')
local window_state = require('marginalia.window.state')

local M = {}

local function copy(value)
    if value == nil then
        return nil
    end

    return vim.deepcopy(value)
end

---@param winid? integer
---@return table?
function M.snapshot(winid)
    local state = window_state.get(winid)

    if not state then
        return nil
    end

    local context_result = state.semantic.context
    local context_frames = context_result and context_result.frames or {}
    local cursor_row = state.cursor.row or 1

    return {
        winid = state.winid,
        bufnr = state.bufnr,
        cursor = copy(state.cursor),
        context = {
            result = copy(context_result),
            candidates = context_normalize.candidates(context_frames, cursor_row),
        },
        viewport = {
            projection = copy(state.viewport.applied_projection),
            post_apply_view = copy(state.viewport.post_apply_view),
        },
        render = {
            plan = copy(state.render.plan),
            artifact = copy(state.render.artifact),
            provider = render_provider.debug_window(state.winid),
        },
        transaction = copy(state.transaction),
    }
end

return M
