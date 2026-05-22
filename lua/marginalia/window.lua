local config = require('marginalia.config')
local context = require('marginalia.context')
local policy = require('marginalia.policy')
local renderer = require('marginalia.renderer')

local M = {}

---@class marginalia.WindowState
---@field winid integer
---@field bufnr integer
---@field ns integer
---@field previous_conceallevel integer
---@field conceallevel_applied boolean
---@field last_cursor_row? integer
---@field last_winline? integer
---@field last_context? marginalia.ContextResult
---@field last_plan? { protected_rows: integer[], hidden_ranges: marginalia.HiddenRange[] }
---@field last_context_topline? integer
---@field last_logical_topline? integer

---@type table<integer, marginalia.WindowState>
local windows = {}

---@param winid? integer
---@return integer
local function normalize_winid(winid)
    if not winid or winid == 0 then
        return vim.api.nvim_get_current_win()
    end

    return winid
end

---@param winid integer
---@return boolean
local function valid_win(winid)
    return type(winid) == 'number' and vim.api.nvim_win_is_valid(winid)
end

---@param ns integer
---@param winid integer
local function scope_namespace_to_window(ns, winid)
    if vim.api.nvim__ns_set then
        pcall(vim.api.nvim__ns_set, ns, { wins = { winid } })
    end
end

---@param winid integer
---@return integer
local function namespace_for(winid)
    local ns = renderer.namespace('win.' .. tostring(winid))
    scope_namespace_to_window(ns, winid)
    return ns
end

---@param frames marginalia.ContextFrame[]
---@return marginalia.ContextFrame[]
local function policy_context_frames(frames)
    local result = {}
    local seen = {}
    local previous_row

    for _, frame in ipairs(frames) do
        local row = frame.row or (frame.range and frame.range.start_row)

        if type(row) == 'number' then
            local skip_bare_compound = not seen[row]
                and frame.type == 'compound_statement'
                and previous_row
                and row ~= previous_row + 1

            if not skip_bare_compound then
                result[#result + 1] = frame

                if not seen[row] then
                    seen[row] = true
                    previous_row = row
                end
            end
        end
    end

    return result
end

---@param frames marginalia.ContextFrame[]
---@param topline integer
---@return integer[]
local function display_context_rows(frames, topline)
    local rows = {}
    local seen = {}
    local previous_row

    for _, frame in ipairs(frames) do
        local row = frame.row or (frame.range and frame.range.start_row)

        if type(row) == 'number' and not seen[row] and row < topline + #rows then
            local skip_bare_compound = frame.type == 'compound_statement' and previous_row and row ~= previous_row + 1

            if not skip_bare_compound then
                rows[#rows + 1] = row
                seen[row] = true
                previous_row = row
            end
        end
    end

    return rows
end

---@param frames marginalia.ContextFrame[]
---@param cursor_row integer
---@param topline integer
---@param line_count integer
---@param resolved marginalia.Config
---@return integer, integer, integer?
local function plan_bounds(frames, cursor_row, topline, line_count, resolved)
    if resolved.scope == 'full_buffer' then
        return 1, line_count, nil
    end

    local context_rows = display_context_rows(frames, topline)
    local start_row = math.min(cursor_row, topline)

    for _, row in ipairs(context_rows) do
        if row < start_row then
            start_row = row
        end
    end

    local end_row = topline + #context_rows - 1

    if not resolved.respect_scrolloff then
        local has_context_in_viewport = false

        for _, frame in ipairs(policy_context_frames(frames)) do
            local row = frame.row or (frame.range and frame.range.start_row)

            if type(row) == 'number' and row >= topline then
                has_context_in_viewport = true
                break
            end
        end

        if not has_context_in_viewport then
            end_row = topline - 1
        end
    end

    return math.max(1, start_row), math.min(end_row, line_count), context_rows[1]
end

---@param winid integer
---@param cursor_row integer
---@param line_count integer
---@param resolved marginalia.Config
---@param minimum_row? integer
---@return marginalia.ProtectedRange[]
local function viewport_protections(winid, cursor_row, line_count, resolved, minimum_row)
    if not resolved.respect_scrolloff then
        return {}
    end

    local scrolloff = vim.wo[winid].scrolloff

    if scrolloff <= 0 then
        return {}
    end

    return {
        {
            start_row = math.max(minimum_row or 1, cursor_row - scrolloff),
            end_row = math.min(line_count, cursor_row + scrolloff),
        },
    }
end

---@param state marginalia.WindowState
---@param cursor_row integer
local function record_cursor_row(state, cursor_row)
    state.last_cursor_row = cursor_row
    state.last_winline = vim.fn.winline()
end

---@param state marginalia.WindowState
---@param cursor_row integer
---@return integer?
local function target_winline(state, cursor_row)
    if not state.last_cursor_row or not state.last_winline then
        return nil
    end

    local cursor_delta = cursor_row - state.last_cursor_row

    if math.abs(cursor_delta) ~= 1 then
        return nil
    end

    return math.max(1, state.last_winline + cursor_delta)
end

---@param target integer
---@return integer
local function stabilize_view_to_target(target)
    local current = vim.fn.winline()

    while current ~= target do
        local view = vim.fn.winsaveview()
        local next_topline = view.topline

        if current > target then
            next_topline = view.topline + 1
        elseif view.topline > 1 then
            next_topline = view.topline - 1
        else
            break
        end

        view.topline = next_topline
        vim.fn.winrestview(view)

        local next_current = vim.fn.winline()

        if next_current == current then
            break
        end

        current = next_current
    end

    return current
end

---@class marginalia.ApplyContext
---@field bufnr integer
---@field state marginalia.WindowState
---@field resolved marginalia.Config
---@field context_result marginalia.ContextResult
---@field cursor_row integer
---@field logical_topline integer
---@field start_row integer
---@field end_row integer
---@field target_topline? integer
---@field protected_ranges marginalia.ProtectedRange[]

---@param apply_context marginalia.ApplyContext
---@param protected_rows integer[]
---@return { protected_rows: integer[], hidden_ranges: marginalia.HiddenRange[] }
local function apply_plan(apply_context, protected_rows)
    local context_frames = policy_context_frames(apply_context.context_result.frames)
    local plan = policy.plan({
        frames = context_frames,
        cursor_row = apply_context.cursor_row,
        protected_ranges = apply_context.protected_ranges,
        protected_rows = protected_rows,
        start_row = apply_context.start_row,
        end_row = apply_context.end_row,
    })

    renderer.apply(
        apply_context.bufnr,
        apply_context.state.ns,
        plan.hidden_ranges,
        { priority = apply_context.resolved.priority }
    )
    return plan
end

---@param apply_context marginalia.ApplyContext
---@param target integer?
---@return { protected_rows: integer[], hidden_ranges: marginalia.HiddenRange[] }
local function apply_stable_plan(apply_context, target)
    local protected_rows = {}
    local plan = apply_plan(apply_context, protected_rows)

    if apply_context.target_topline then
        vim.fn.winrestview({ topline = apply_context.target_topline })
    end

    if not target then
        return plan
    end

    local current_winline = stabilize_view_to_target(target)
    local reveal_row = apply_context.cursor_row - 1

    while current_winline < target and reveal_row >= 1 do
        protected_rows[#protected_rows + 1] = reveal_row
        plan = apply_plan(apply_context, protected_rows)
        current_winline = stabilize_view_to_target(target)
        reveal_row = reveal_row - 1
    end

    return plan
end

---@param state marginalia.WindowState
---@param resolved marginalia.Config
local function apply_conceallevel(state, resolved)
    if not valid_win(state.winid) or state.conceallevel_applied then
        return
    end

    if vim.wo[state.winid].conceallevel < resolved.conceallevel then
        vim.wo[state.winid].conceallevel = resolved.conceallevel
        state.conceallevel_applied = true
    end
end

---@param state marginalia.WindowState
local function restore_conceallevel(state)
    if not valid_win(state.winid) or not state.conceallevel_applied then
        return
    end

    vim.wo[state.winid].conceallevel = state.previous_conceallevel
    state.conceallevel_applied = false
end

---@param state marginalia.WindowState
---@param row integer
---@return boolean
local function row_was_hidden(state, row)
    local plan = state.last_plan

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

---@param winid? integer
---@return marginalia.WindowState?
function M.state(winid)
    return windows[normalize_winid(winid)]
end

---@param winid? integer
---@return boolean
function M.is_attached(winid)
    return M.state(winid) ~= nil
end

---@param winid? integer
---@param opts? marginalia.Config
---@return boolean
function M.attach(winid, opts)
    winid = normalize_winid(winid)

    if not valid_win(winid) then
        return false
    end

    local resolved = config.normalize(opts)
    local state = windows[winid]

    if not state then
        state = {
            winid = winid,
            bufnr = vim.api.nvim_win_get_buf(winid),
            ns = namespace_for(winid),
            previous_conceallevel = vim.wo[winid].conceallevel,
            conceallevel_applied = false,
        }
        windows[winid] = state
    end

    M.refresh(winid, resolved)
    return true
end

---@param winid? integer
function M.detach(winid)
    winid = normalize_winid(winid)

    local state = windows[winid]

    if not state then
        return
    end

    renderer.clear(state.bufnr, state.ns)

    restore_conceallevel(state)

    windows[winid] = nil
end

---@param winid? integer
---@param opts? marginalia.Config|{ frames?: marginalia.ContextFrame[], context_result?: marginalia.ContextResult }
---@return { protected_rows: integer[], hidden_ranges: marginalia.HiddenRange[] }?
function M.refresh(winid, opts)
    winid = normalize_winid(winid)

    if not valid_win(winid) then
        windows[winid] = nil
        return nil
    end

    local state = windows[winid]

    if not state then
        return nil
    end

    local resolved = config.normalize(opts)
    local bufnr = vim.api.nvim_win_get_buf(winid)
    state.bufnr = bufnr

    local cursor_row = vim.api.nvim_win_get_cursor(winid)[1]
    local line_count = vim.api.nvim_buf_line_count(bufnr)
    local context_result = opts and opts.context_result or nil

    if not context_result then
        if opts and opts.frames then
            context_result = { frames = opts.frames }
        else
            context_result = context.for_window(vim.tbl_deep_extend('force', resolved, {
                bufnr = bufnr,
                winid = winid,
            }))
        end
    end

    state.last_context = context_result

    if #context_result.frames == 0 then
        renderer.clear(bufnr, state.ns)
        restore_conceallevel(state)
        state.last_plan = { protected_rows = {}, hidden_ranges = {} }
        record_cursor_row(state, cursor_row)
        return state.last_plan
    end

    local view_topline = vim.fn.winsaveview().topline
    local topline = view_topline

    if
        state.last_logical_topline
        and (state.last_context_topline == view_topline or row_was_hidden(state, view_topline))
    then
        topline = state.last_logical_topline
    end

    if resolved.respect_scrolloff then
        local scrolloff = vim.wo[winid].scrolloff

        if scrolloff > 0 then
            local height = vim.api.nvim_win_get_height(winid)
            topline = math.max(topline, cursor_row - height + scrolloff + 1)
        end
    end

    local start_row, end_row, target_topline =
        plan_bounds(context_result.frames, cursor_row, topline, line_count, resolved)
    local protected_ranges = viewport_protections(winid, cursor_row, line_count, resolved, end_row + 1)
    local desired_winline = target_winline(state, cursor_row)
    local plan = apply_stable_plan({
        bufnr = bufnr,
        state = state,
        resolved = resolved,
        context_result = context_result,
        cursor_row = cursor_row,
        logical_topline = topline,
        start_row = start_row,
        end_row = end_row,
        target_topline = target_topline,
        protected_ranges = protected_ranges,
    }, desired_winline)

    if #plan.hidden_ranges > 0 then
        apply_conceallevel(state, resolved)
    else
        restore_conceallevel(state)
    end

    if target_topline then
        vim.fn.winrestview({ topline = target_topline })

        if desired_winline then
            stabilize_view_to_target(desired_winline)
        end
    end

    state.last_plan = plan
    state.last_context_topline = target_topline
    state.last_logical_topline = topline
    record_cursor_row(state, cursor_row)

    return plan
end

---@param winid? integer
---@param opts? marginalia.Config
---@return boolean
function M.toggle(winid, opts)
    winid = normalize_winid(winid)

    if M.is_attached(winid) then
        M.detach(winid)
        return false
    end

    M.attach(winid, opts)
    return true
end

return M
