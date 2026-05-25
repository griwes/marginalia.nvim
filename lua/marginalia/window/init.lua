local config = require('marginalia.config')
local context = require('marginalia.context')
local render_apply = require('marginalia.render.apply')
local render_provider = require('marginalia.render.provider')
local window_apply = require('marginalia.window.apply')
local window_debug = require('marginalia.window.debug')
local window_event = require('marginalia.window.event')
local window_planner = require('marginalia.window.planner')
local window_snapshot = require('marginalia.window.snapshot')
local window_state = require('marginalia.window.state')

local M = {}

---@param winid? integer
---@return marginalia.WindowState?
function M.state(winid)
    return window_state.get(winid)
end

---@param winid? integer
---@return table?
function M.debug_snapshot(winid)
    return window_debug.snapshot(winid)
end

---@param winid? integer
---@return boolean
function M.is_attached(winid)
    return window_state.is_attached(winid)
end

---@param winid? integer
---@param opts? marginalia.Config
---@return boolean
function M.attach(winid, opts)
    winid = window_state.normalize_winid(winid)

    if not window_state.valid_win(winid) then
        return false
    end

    local resolved = config.normalize(opts)
    window_state.ensure(winid)

    M.refresh(winid, resolved)
    return true
end

---@param winid? integer
function M.detach(winid)
    winid = window_state.normalize_winid(winid)

    local state = window_state.get(winid)

    if not state then
        return
    end

    render_apply.clear_state(state)

    render_apply.restore_conceallevel(state)
    render_apply.restore_scrolloff(state)

    window_state.remove(winid)
end

---@param state marginalia.WindowState
---@param snapshot marginalia.WindowSnapshot
---@param classification marginalia.RefreshEventClassification
---@return boolean
local function reassert_scroll_echo_if_needed(state, snapshot, classification)
    if classification.kind ~= 'transaction_echo' then
        return false
    end

    local projection = state.viewport.applied_projection
    local target_topline = projection and projection.actual_viewport and projection.actual_viewport.topline
    local plan = state.render.plan
    local current_topline = snapshot.raw_view.topline

    if
        not target_topline
        or current_topline == target_topline
        or #(plan and plan.hidden_ranges or {}) == 0
        or state.transaction.scroll_echo_reasserted_epoch == state.transaction.epoch
    then
        return false
    end

    render_apply.restore_target_topline(state, target_topline)

    local post_apply_view = vim.fn.winsaveview()

    window_state.record_scroll_echo_reassertion(state, {
        raw_topline = post_apply_view.topline,
        post_apply_view = post_apply_view,
        cursor_row = snapshot.cursor_row,
        cursor_winline = vim.fn.winline(),
        native_cursor_winline = snapshot.native_winline,
    })

    return true
end

---@param winid? integer
---@param opts? marginalia.Config|{ frames?: marginalia.ContextFrame[], context_result?: marginalia.ContextResult, _event?: string, _logical_scroll_delta?: integer }
---@return { visible_rows: integer[], hidden_ranges: marginalia.HiddenRange[] }?
local function refresh_current_window(winid, opts)
    local state = window_state.get(winid)

    if not state then
        return nil
    end

    local resolved = config.normalize(opts)
    local snapshot = window_snapshot.capture(winid)
    local bufnr = snapshot.bufnr
    local previous_bufnr = state.bufnr

    if previous_bufnr ~= bufnr then
        if previous_bufnr and vim.api.nvim_buf_is_valid(previous_bufnr) then
            render_apply.clear(previous_bufnr, state.ns)
            render_provider.clear_buffer(previous_bufnr)
        end

        window_state.rebind_buffer(state, bufnr)
    end

    state.bufnr = bufnr

    local cursor_row = snapshot.cursor_row
    local context_result = opts and opts.context_result or nil
    local raw_previous_view = snapshot.raw_view
    local refresh_event = opts and opts._event or nil
    local refresh_events = opts and opts._events or nil
    local event_classification = window_event.classify_refresh(state, {
        refresh_event = refresh_event,
        refresh_events = refresh_events,
        cursor_row = cursor_row,
        raw_topline = raw_previous_view.topline,
    })

    if event_classification.kind == 'transaction_echo' then
        reassert_scroll_echo_if_needed(state, snapshot, event_classification)
        return state.render.plan
    end

    if not context_result then
        if opts and opts.frames then
            context_result = { frames = opts.frames }
        else
            context_result = context.for_window(vim.tbl_deep_extend('force', resolved, {
                bufnr = bufnr,
                winid = winid,
                on_publish = opts and opts._on_context_publish or nil,
            }))
        end
    end

    if refresh_event == 'ContextParsed' and context_result.stale then
        event_classification = window_event.classify({
            event = refresh_event,
            transaction_epoch = state.transaction.epoch,
            cursor_row = cursor_row,
            raw_topline = raw_previous_view.topline,
            context_stale = true,
        })
    end

    state.semantic.context = context_result

    if #context_result.frames == 0 then
        render_apply.clear_state(state)
        render_apply.restore_conceallevel(state)
        render_apply.restore_scrolloff(state)
        render_apply.restore_view(window_snapshot.normalized_view(winid))
        window_state.record_empty_result(state, {
            cursor_row = cursor_row,
            raw_topline = vim.fn.winsaveview().topline,
        })
        return state.render.plan
    end

    local scrolloff = 0

    if resolved.viewport.respect_scrolloff then
        scrolloff = window_state.effective_scrolloff(state)
    end

    -- Measure raw row heights for the next projection, not the old materialized
    -- conceal marks from the previous projection.
    render_provider.clear_buffer(bufnr)

    local planner_projection = window_planner.project({
        snapshot = snapshot,
        state = state,
        context_frames = context_result.frames,
        scrolloff = scrolloff,
        event = event_classification.planner_event,
        logical_scroll_delta = opts and opts._logical_scroll_delta or nil,
    })
    local plan = window_apply.apply_projection({
        bufnr = bufnr,
        state = state,
        projection = planner_projection,
        priority = resolved.render.priority,
        prime = true,
    })

    render_apply.apply_window_options(state, plan, resolved.render.conceallevel)

    local has_hidden_ranges = #(plan.hidden_ranges or {}) > 0

    if has_hidden_ranges and planner_projection.actual_viewport and planner_projection.actual_viewport.topline then
        render_apply.restore_target_topline(state, planner_projection.actual_viewport.topline)
    end

    local post_apply_view = vim.fn.winsaveview()

    window_state.record_apply_result(state, {
        plan = plan,
        context_topline = planner_projection.context_rows[1],
        logical_topline = planner_projection.virtual_viewport.topline,
        raw_topline = post_apply_view.topline,
        previous_raw_topline = raw_previous_view.topline,
        post_apply_view = post_apply_view,
        cursor_row = cursor_row,
        cursor_winline = planner_projection.cursor_physical_row,
        native_cursor_winline = snapshot.native_winline,
        scrolloff = planner_projection.scrolloff,
    })

    return plan
end

---@param winid? integer
---@param opts? marginalia.Config|{ frames?: marginalia.ContextFrame[], context_result?: marginalia.ContextResult, _event?: string }
---@return { visible_rows: integer[], hidden_ranges: marginalia.HiddenRange[] }?
function M.refresh(winid, opts)
    winid = window_state.normalize_winid(winid)

    if window_state.drop_invalid(winid) then
        render_provider.remove_window(winid)
        return nil
    end

    return vim.api.nvim_win_call(winid, function()
        return refresh_current_window(winid, opts)
    end)
end

---@param winid? integer
---@param opts? marginalia.Config
---@return boolean
function M.toggle(winid, opts)
    winid = window_state.normalize_winid(winid)

    if M.is_attached(winid) then
        M.detach(winid)
        return false
    end

    M.attach(winid, opts)
    return true
end

return M
