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
    local has_pinned_context = #(projection and projection.context_rows or {}) > 0
    local has_hidden_ranges = #(plan and plan.hidden_ranges or {}) > 0

    if
        not target_topline
        or current_topline == target_topline
        or (not has_pinned_context and not has_hidden_ranges)
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
        jumplist = snapshot.jumplist,
    })

    return true
end

---@param projection marginalia.ViewportProjection
---@param plan { hidden_ranges?: marginalia.HiddenRange[] }
---@param raw_topline integer
---@return integer?
local function target_topline_to_restore(projection, plan, raw_topline)
    local target_topline = projection.actual_viewport and projection.actual_viewport.topline

    if not target_topline then
        return nil
    end

    local has_hidden_ranges = #(plan.hidden_ranges or {}) > 0
    local has_pinned_context = #(projection.context_rows or {}) > 0

    if has_hidden_ranges then
        return target_topline
    end

    if has_pinned_context and target_topline ~= raw_topline then
        return target_topline
    end

    return nil
end

---@param rows integer[]?
---@param row integer
---@return integer?
local function row_index(rows, row)
    for index, candidate in ipairs(rows or {}) do
        if candidate == row then
            return index
        end
    end

    return nil
end

---@param entry any
---@return string?
local function jumplist_entry_key(entry)
    if type(entry) ~= 'table' or type(entry.bufnr) ~= 'number' or type(entry.lnum) ~= 'number' then
        return nil
    end

    return table.concat({
        tostring(entry.bufnr),
        tostring(entry.lnum),
        tostring(entry.col or 0),
        tostring(entry.coladd or 0),
    }, ':')
end

---@param state marginalia.WindowState
---@param snapshot marginalia.WindowSnapshot
---@return boolean
local function cursor_moved_by_native_jump(state, snapshot)
    local prior_row = state.cursor and state.cursor.row
    local prior_jumplist = state.cursor and state.cursor.jumplist
    local next_jumplist = snapshot.jumplist

    if not prior_row or not prior_jumplist or not next_jumplist then
        return false
    end

    local current = next_jumplist.current

    if type(current) ~= 'table' or current.bufnr ~= snapshot.bufnr or current.lnum ~= prior_row then
        return false
    end

    return next_jumplist.index ~= prior_jumplist.index
        or next_jumplist.length ~= prior_jumplist.length
        or jumplist_entry_key(current) ~= jumplist_entry_key(prior_jumplist.current)
end

---@param state marginalia.WindowState
---@param snapshot marginalia.WindowSnapshot
---@param classification marginalia.RefreshEventClassification
---@return marginalia.WindowSnapshot?, integer?
local function recover_cursor_from_skipped_conceal(state, snapshot, classification)
    if classification.kind ~= 'user_intent' or classification.planner_event ~= 'CursorMoved' then
        return nil, nil
    end

    if cursor_moved_by_native_jump(state, snapshot) then
        return nil, nil
    end

    if
        not state.cursor
        or not state.cursor.row
        or not state.cursor.physical_row
        or not state.render
        or not state.render.plan
        or #(state.render.plan.hidden_ranges or {}) == 0
    then
        return nil, nil
    end

    if snapshot.cursor_row >= state.cursor.row then
        return nil, nil
    end

    local visible_rows = state.render.plan.visible_rows or {}
    local prior_index = row_index(visible_rows, state.cursor.row)
    local current_index = row_index(visible_rows, snapshot.cursor_row)

    if not prior_index or not current_index or current_index >= prior_index then
        return nil, nil
    end

    local logical_delta = current_index - prior_index
    local target_row = state.cursor.row + logical_delta

    if target_row <= snapshot.cursor_row or target_row >= state.cursor.row then
        return nil, nil
    end

    local cursor = vim.api.nvim_win_get_cursor(snapshot.winid)
    vim.api.nvim_win_set_cursor(snapshot.winid, { target_row, cursor[2] })

    return window_snapshot.capture(snapshot.winid), state.cursor.physical_row
end

---@param state marginalia.WindowState
---@param snapshot marginalia.WindowSnapshot
---@param native_scroll_delta integer?
---@return marginalia.WindowSnapshot?, integer?
local function advance_cursor_for_blocked_scroll(state, snapshot, native_scroll_delta)
    if type(native_scroll_delta) ~= 'number' or native_scroll_delta <= 0 then
        return nil, nil
    end

    if not state.cursor or state.cursor.row ~= snapshot.cursor_row then
        return nil, nil
    end

    local projection = state.viewport and state.viewport.applied_projection
    local context_rows = projection and projection.context_rows or {}
    local cursor_is_logical_top = state.cursor.physical_row == #context_rows + 1

    if not cursor_is_logical_top or snapshot.cursor_row >= snapshot.line_count then
        return nil, nil
    end

    local target_row = math.min(snapshot.line_count, snapshot.cursor_row + math.floor(native_scroll_delta))

    if target_row == snapshot.cursor_row then
        return nil, nil
    end

    local cursor = vim.api.nvim_win_get_cursor(snapshot.winid)
    vim.api.nvim_win_set_cursor(snapshot.winid, { target_row, cursor[2] })

    return window_snapshot.capture(snapshot.winid), state.cursor.physical_row
end

---@param winid? integer
---@param opts? marginalia.Config|{ frames?: marginalia.ContextFrame[], context_result?: marginalia.ContextResult, _event?: string, _logical_scroll_delta?: integer, _native_scroll_delta?: integer }
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
            render_provider.clear_window_marks(state, previous_bufnr)
        end

        render_apply.restore_conceallevel(state)
        render_apply.restore_scrolloff(state)
        window_state.rebind_buffer(state, bufnr)
    end

    state.bufnr = bufnr

    local cursor_row = snapshot.cursor_row
    local context_result = opts and opts.context_result or nil
    local raw_previous_view = snapshot.raw_view
    local refresh_event = opts and opts._event or nil
    local native_scroll_delta = opts and opts._native_scroll_delta or nil
    local forced_cursor_physical_row = nil
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

    if event_classification.kind == 'user_intent' and event_classification.planner_event == 'WinScrolled' then
        local advanced_snapshot, physical_row = advance_cursor_for_blocked_scroll(state, snapshot, native_scroll_delta)

        if advanced_snapshot and physical_row then
            snapshot = advanced_snapshot
            cursor_row = snapshot.cursor_row
            raw_previous_view = snapshot.raw_view
            forced_cursor_physical_row = physical_row
            event_classification = {
                kind = 'user_intent',
                primary_event = 'CursorMoved',
                planner_event = 'CursorMoved',
            }
        end
    end

    local recovered_snapshot, recovered_physical_row =
        recover_cursor_from_skipped_conceal(state, snapshot, event_classification)

    if recovered_snapshot and recovered_physical_row then
        snapshot = recovered_snapshot
        cursor_row = snapshot.cursor_row
        raw_previous_view = snapshot.raw_view
        forced_cursor_physical_row = recovered_physical_row
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
            jumplist = snapshot.jumplist,
        })
        return state.render.plan
    end

    local scrolloff = 0

    if resolved.viewport.respect_scrolloff then
        scrolloff = window_state.effective_scrolloff(state)
    end

    -- Measure raw row heights for the next projection, not the old materialized
    -- conceal marks from the previous projection.
    render_provider.clear_window_marks(state, bufnr)

    local planner_projection = window_planner.project({
        snapshot = snapshot,
        state = state,
        context_frames = context_result.frames,
        scrolloff = scrolloff,
        event = event_classification.planner_event,
        logical_scroll_delta = opts and opts._logical_scroll_delta or nil,
        forced_cursor_physical_row = forced_cursor_physical_row,
    })
    local plan = window_apply.apply_projection({
        bufnr = bufnr,
        state = state,
        projection = planner_projection,
        priority = resolved.render.priority,
        prime = true,
    })

    if plan.render_error then
        render_apply.restore_conceallevel(state)
        render_apply.restore_scrolloff(state)
        render_apply.restore_view(raw_previous_view)
        window_state.record_empty_result(state, {
            cursor_row = cursor_row,
            raw_topline = raw_previous_view.topline,
            jumplist = snapshot.jumplist,
        })
        state.render.plan = plan
        state.viewport.applied_projection = nil
        state.viewport.context_topline = nil
        state.viewport.logical_topline = nil
        state.viewport.post_apply_view = nil
        return plan
    end

    render_apply.apply_window_options(state, plan, resolved.render.conceallevel)

    local target_topline = target_topline_to_restore(planner_projection, plan, raw_previous_view.topline)

    if target_topline then
        render_apply.restore_target_topline(state, target_topline)
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
        jumplist = snapshot.jumplist,
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
