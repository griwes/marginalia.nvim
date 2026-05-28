local render_apply = require('marginalia.render.apply')

local M = {}

---@class marginalia.WindowState
---@field winid integer
---@field bufnr integer
---@field ns integer
---@field identity marginalia.WindowIdentityState
---@field options marginalia.WindowOptionState
---@field cursor marginalia.WindowCursorState
---@field semantic marginalia.WindowSemanticState
---@field viewport marginalia.WindowViewportState
---@field render marginalia.WindowRenderState
---@field transaction marginalia.WindowTransactionState

---@class marginalia.WindowIdentityState
---@field winid integer
---@field bufnr integer
---@field ns integer

---@class marginalia.WindowOptionState
---@field original_conceallevel integer
---@field conceallevel_applied boolean
---@field original_scrolloff integer
---@field original_global_scrolloff integer
---@field scrolloff_restore_global boolean
---@field scrolloff_suppressed boolean

---@class marginalia.WindowCursorState
---@field row? integer
---@field physical_row? integer
---@field native_physical_row? integer
---@field jumplist? marginalia.WindowJumplistSnapshot

---@class marginalia.WindowSemanticState
---@field context? marginalia.ContextResult

---@class marginalia.WindowViewportState
---@field context_topline? integer
---@field logical_topline? integer
---@field raw_topline? integer
---@field applied_projection? marginalia.ViewportProjection|table
---@field post_apply_view? table

---@class marginalia.WindowRenderState
---@field plan? { visible_rows: integer[], hidden_ranges: marginalia.HiddenRange[] }
---@field artifact? table
---@field provider? table

---@class marginalia.WindowTransactionState
---@field epoch? integer
---@field expected_scroll_echo? { epoch: integer, cursor_row: integer, raw_topline: integer, raw_toplines?: table<integer, true> }
---@field expected_option_echo? { epoch: integer, options: table<string, true> }
---@field pending_option_echoes? table<string, true>
---@field scroll_echo_reasserted_epoch? integer

---@type table<integer, marginalia.WindowState>
local windows = {}

---@param winid? integer
---@return integer
function M.normalize_winid(winid)
    if not winid or winid == 0 then
        return vim.api.nvim_get_current_win()
    end

    return winid
end

---@param winid integer
---@return boolean
function M.valid_win(winid)
    return type(winid) == 'number' and vim.api.nvim_win_is_valid(winid)
end

---@param winid integer
---@return integer
local function namespace_for(winid)
    return render_apply.namespace('win.' .. tostring(winid))
end

---@param winid integer
---@return marginalia.WindowOptionState
local function capture_options(winid)
    local window_scrolloff = vim.wo[winid].scrolloff

    return {
        original_conceallevel = vim.wo[winid].conceallevel,
        conceallevel_applied = false,
        original_scrolloff = window_scrolloff,
        original_global_scrolloff = vim.go.scrolloff,
        scrolloff_restore_global = window_scrolloff == vim.go.scrolloff,
        scrolloff_suppressed = false,
    }
end

---@param winid integer
---@param bufnr integer
---@param ns integer
---@return marginalia.WindowIdentityState
local function identity_state(winid, bufnr, ns)
    return {
        winid = winid,
        bufnr = bufnr,
        ns = ns,
    }
end

---@return marginalia.WindowCursorState
local function cursor_state()
    return {}
end

---@return marginalia.WindowSemanticState
local function semantic_state()
    return {}
end

---@return marginalia.WindowViewportState
local function viewport_state()
    return {}
end

---@return marginalia.WindowRenderState
local function render_state()
    return {}
end

---@return marginalia.WindowTransactionState
local function transaction_state()
    return {}
end

---@param winid? integer
---@return marginalia.WindowState?
function M.get(winid)
    return windows[M.normalize_winid(winid)]
end

---@param winid? integer
---@return boolean
function M.is_attached(winid)
    winid = M.normalize_winid(winid)

    if not M.valid_win(winid) then
        windows[winid] = nil
        return false
    end

    return windows[winid] ~= nil
end

---@param winid integer
---@return marginalia.WindowState?
function M.ensure(winid)
    winid = M.normalize_winid(winid)

    if not M.valid_win(winid) then
        windows[winid] = nil
        return nil
    end

    local state = windows[winid]

    if state then
        return state
    end

    local bufnr = vim.api.nvim_win_get_buf(winid)
    local ns = namespace_for(winid)

    state = {
        winid = winid,
        bufnr = bufnr,
        ns = ns,
        identity = identity_state(winid, bufnr, ns),
        options = capture_options(winid),
        cursor = cursor_state(),
        semantic = semantic_state(),
        viewport = viewport_state(),
        render = render_state(),
        transaction = transaction_state(),
    }

    windows[winid] = state
    return state
end

---@param state marginalia.WindowState
function M.reset_runtime(state)
    state.cursor = cursor_state()
    state.semantic = semantic_state()
    state.viewport = viewport_state()
    state.render = render_state()
    state.transaction = transaction_state()
end

---@param state marginalia.WindowState
---@param bufnr integer
function M.rebind_buffer(state, bufnr)
    state.bufnr = bufnr
    state.identity.bufnr = bufnr
    state.options = capture_options(state.winid)
    M.reset_runtime(state)
end

---@param state marginalia.WindowState
---@param cursor_row integer
---@param winline? integer
---@param native_winline? integer
---@param jumplist? marginalia.WindowJumplistSnapshot
function M.record_cursor_row(state, cursor_row, winline, native_winline, jumplist)
    state.cursor.row = cursor_row
    state.cursor.physical_row = winline or vim.fn.winline()
    state.cursor.native_physical_row = native_winline or state.cursor.physical_row
    state.cursor.jumplist = jumplist
end

---@param state marginalia.WindowState
---@param opts { plan: table, context_topline?: integer, logical_topline: integer, raw_topline: integer, previous_raw_topline?: integer, post_apply_view: table, cursor_row: integer, cursor_winline: integer, native_cursor_winline?: integer, scrolloff?: table, jumplist?: marginalia.WindowJumplistSnapshot }
function M.record_apply_result(state, opts)
    local plan = opts.plan

    state.render.plan = plan
    state.viewport.context_topline = opts.context_topline
    state.viewport.logical_topline = opts.logical_topline
    state.viewport.raw_topline = opts.raw_topline
    state.transaction.epoch = (state.transaction.epoch or 0) + 1
    state.transaction.scroll_echo_reasserted_epoch = nil

    plan.projection.scrolloff = opts.scrolloff
    state.viewport.applied_projection = plan.projection
    state.render.artifact = {
        visible_rows = plan.visible_rows,
        hidden_ranges = plan.hidden_ranges,
    }
    state.viewport.post_apply_view = opts.post_apply_view

    M.record_cursor_row(state, opts.cursor_row, opts.cursor_winline, opts.native_cursor_winline, opts.jumplist)

    state.transaction.expected_scroll_echo = {
        epoch = state.transaction.epoch,
        cursor_row = opts.cursor_row,
        raw_topline = state.viewport.raw_topline,
        raw_toplines = {
            [state.viewport.raw_topline] = true,
            [opts.previous_raw_topline or state.viewport.raw_topline] = true,
        },
    }
    if state.transaction.pending_option_echoes and next(state.transaction.pending_option_echoes) ~= nil then
        state.transaction.expected_option_echo = {
            epoch = state.transaction.epoch,
            options = state.transaction.pending_option_echoes,
        }
    else
        state.transaction.expected_option_echo = nil
    end

    state.transaction.pending_option_echoes = nil
end

---@param state marginalia.WindowState
---@param opts { raw_topline: integer, cursor_row: integer, cursor_winline: integer, native_cursor_winline?: integer, post_apply_view: table, jumplist?: marginalia.WindowJumplistSnapshot }
function M.record_scroll_echo_reassertion(state, opts)
    local epoch = state.transaction.epoch

    state.viewport.raw_topline = opts.raw_topline
    state.viewport.post_apply_view = opts.post_apply_view

    M.record_cursor_row(state, opts.cursor_row, opts.cursor_winline, opts.native_cursor_winline, opts.jumplist)

    state.transaction.scroll_echo_reasserted_epoch = epoch
    state.transaction.expected_scroll_echo = {
        epoch = epoch,
        cursor_row = opts.cursor_row,
        raw_topline = opts.raw_topline,
        raw_toplines = {
            [opts.raw_topline] = true,
        },
    }

    if state.transaction.pending_option_echoes and next(state.transaction.pending_option_echoes) ~= nil then
        state.transaction.expected_option_echo = {
            epoch = epoch,
            options = state.transaction.pending_option_echoes,
        }
    end

    state.transaction.pending_option_echoes = nil
end

---@param state marginalia.WindowState
---@param opts { cursor_row: integer, raw_topline: integer, jumplist?: marginalia.WindowJumplistSnapshot }
function M.record_empty_result(state, opts)
    state.render.plan = { visible_rows = {}, hidden_ranges = {} }
    M.record_cursor_row(state, opts.cursor_row, nil, nil, opts.jumplist)
    state.viewport.raw_topline = opts.raw_topline
end

---@param state marginalia.WindowState
---@param row integer
---@return boolean
function M.row_was_hidden(state, row)
    local plan = state.render.plan

    if not plan then
        return false
    end

    for _, range in ipairs(plan.hidden_ranges or {}) do
        if row >= range.start_row and row <= range.end_row then
            return true
        end
    end

    return false
end

---@param state marginalia.WindowState
---@return integer
function M.effective_scrolloff(state)
    local options = state.options

    if options.scrolloff_suppressed then
        if options.scrolloff_restore_global then
            return math.max(options.original_scrolloff, vim.go.scrolloff)
        end

        return options.original_scrolloff
    end

    if not M.valid_win(state.winid) then
        return 0
    end

    return vim.wo[state.winid].scrolloff
end

---@param winid? integer
function M.remove(winid)
    winid = M.normalize_winid(winid)
    windows[winid] = nil
end

---@param winid? integer
---@return boolean
function M.drop_invalid(winid)
    winid = M.normalize_winid(winid)

    if M.valid_win(winid) then
        return false
    end

    windows[winid] = nil
    return true
end

return M
