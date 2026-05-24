local context_normalize = require('marginalia.context.normalize')

local M = {}

local frame_start_row = context_normalize.frame_start_row
local frame_end_row = context_normalize.frame_end_row

---@class marginalia.ViewportProjection
---@field reason string
---@field context_rows integer[]
---@field selected_candidates marginalia.ViewportCandidate[]
---@field selected_frames marginalia.ContextFrame[]
---@field virtual_viewport { topline: integer, botline: integer }
---@field actual_viewport { topline: integer }
---@field conceal_scope { start_row: integer, end_row: integer }
---@field visible_rows integer[]
---@field cursor_physical_row integer
---@field scrolloff { user: integer, effective: integer }

---@param value integer
---@param minimum integer
---@param maximum integer
---@return integer
local function clamp(value, minimum, maximum)
    if minimum > maximum then
        return minimum
    end

    return math.min(maximum, math.max(minimum, value))
end

---@param rows integer[]
---@return integer[]
local function sorted_unique_rows(rows)
    local seen = {}
    local result = {}

    for _, row in ipairs(rows) do
        if type(row) == 'number' and row > 0 and not seen[row] then
            seen[row] = true
            result[#result + 1] = row
        end
    end

    table.sort(result)
    return result
end

---@param rows integer[]
---@return integer[]
local function copy_rows(rows)
    local result = {}

    for index, row in ipairs(rows) do
        result[index] = row
    end

    return result
end

---@param row integer
---@param rows integer[]
---@return boolean
local function has_row(row, rows)
    for _, candidate_row in ipairs(rows) do
        if candidate_row == row then
            return true
        end
    end

    return false
end

---@param frame marginalia.ContextFrame
---@return marginalia.ContextFrame
local function copy_frame(frame)
    local copy = vim.tbl_extend('force', {}, frame)

    if frame.range then
        copy.range = vim.tbl_extend('force', {}, frame.range)
    end

    return copy
end

---@param candidates marginalia.ViewportCandidate[]
---@param rows integer[]
---@return marginalia.ContextFrame[]
function M.selected_frames(candidates, rows)
    local frames = {}

    for _, candidate in ipairs(candidates) do
        local first_row
        local last_row

        for _, row in ipairs(candidate.rows) do
            if has_row(row, rows) then
                first_row = first_row or row
                last_row = row
            end
        end

        if first_row and last_row then
            local frame = copy_frame(candidate.frame)

            if frame.range then
                frame.range.start_row = first_row
                frame.range.end_row = last_row + 1
                frame.range.end_col = 0
            else
                frame.row = first_row
            end

            frames[#frames + 1] = frame
        end
    end

    return frames
end

---@param frames marginalia.ContextFrame[]
---@param rows integer[]
---@return marginalia.ContextFrame[]
function M.displayed_frames_from_rows(frames, rows)
    local displayed_rows = {}

    for _, row in ipairs(rows) do
        displayed_rows[row] = true
    end

    local displayed_frames = {}

    for _, frame in ipairs(frames) do
        local row = frame_start_row(frame.range, frame.row)

        if displayed_rows[row] then
            local displayed_frame = copy_frame(frame)

            if displayed_frame.range then
                local end_row = frame_end_row(displayed_frame.range, row)
                local last_displayed_row = row

                for range_row = row, end_row do
                    if displayed_rows[range_row] then
                        last_displayed_row = range_row
                    elseif range_row > row then
                        break
                    end
                end

                displayed_frame.range.end_row = last_displayed_row + 1
                displayed_frame.range.end_col = 0
            end

            displayed_frames[#displayed_frames + 1] = displayed_frame
        end
    end

    return displayed_frames
end

---@param candidates marginalia.ViewportCandidate[]
---@param capacity integer
---@return integer[], marginalia.ViewportCandidate[]
function M.allocate_context_rows(candidates, capacity)
    capacity = math.max(0, capacity or 0)

    if capacity == 0 then
        return {}, {}
    end

    local selected_rows = {}
    local selected_candidates = {}
    local remaining = capacity

    for index = #candidates, 1, -1 do
        local candidate = candidates[index]

        if candidate.height <= remaining then
            table.insert(selected_candidates, 1, candidate)

            for row_index = #candidate.rows, 1, -1 do
                table.insert(selected_rows, 1, candidate.rows[row_index])
            end

            remaining = remaining - candidate.height
        elseif #selected_candidates == 0 and remaining > 0 then
            table.insert(selected_candidates, 1, candidate)

            for row_index = math.min(#candidate.rows, remaining), 1, -1 do
                table.insert(selected_rows, 1, candidate.rows[row_index])
            end

            remaining = 0
        end

        if remaining == 0 then
            break
        end
    end

    return sorted_unique_rows(selected_rows), selected_candidates
end

---@param candidates marginalia.ViewportCandidate[]
---@param topline integer
---@return marginalia.ViewportCandidate[]
function M.candidates_above_virtual_viewport(candidates, topline)
    local result = {}

    for _, candidate in ipairs(candidates or {}) do
        local rows = {}

        for _, row in ipairs(candidate.rows or {}) do
            if row < topline then
                rows[#rows + 1] = row
            end
        end

        if #rows > 0 then
            local copy = vim.tbl_extend('force', {}, candidate)

            copy.rows = rows
            copy.height = #rows
            result[#result + 1] = copy
        end
    end

    return result
end

---@param opts { cursor_row: integer, line_count: integer, winheight: integer, cursor_physical_row: integer, candidates: marginalia.ViewportCandidate[], context_capacity: integer }
---@return integer[], marginalia.ViewportCandidate[], integer, integer
function M.project_context_and_body(opts)
    local context_rows = {}
    local selected_candidates = {}
    local body_topline = opts.cursor_row - math.max(0, opts.cursor_physical_row - 1)
    local body_botline = opts.cursor_row

    for _ = 1, opts.context_capacity + 1 do
        local body_rows_above_cursor = math.max(0, opts.cursor_physical_row - #context_rows - 1)
        local next_body_topline = math.max(1, opts.cursor_row - body_rows_above_cursor)
        local next_body_botline = math.min(opts.line_count, next_body_topline + opts.winheight - #context_rows - 1)
        local pinned_candidates = M.candidates_above_virtual_viewport(opts.candidates, next_body_topline)
        local next_context_rows, next_selected_candidates =
            M.allocate_context_rows(pinned_candidates, opts.context_capacity)

        if #next_context_rows == #context_rows and next_body_topline == body_topline then
            body_topline = next_body_topline
            body_botline = next_body_botline
            selected_candidates = next_selected_candidates
            break
        end

        context_rows = next_context_rows
        selected_candidates = next_selected_candidates
        body_topline = next_body_topline
        body_botline = next_body_botline
    end

    return context_rows, selected_candidates, body_topline, body_botline
end

---@param opts { cursor_row: integer, line_count: integer, winheight: integer, raw_topline: integer, current_physical_row?: integer, prior_cursor_row?: integer, prior_physical_row?: integer, prior_virtual_topline?: integer, effective_scrolloff?: integer, scrolloff?: integer, event?: string, candidates?: marginalia.ViewportCandidate[] }
---@return string
local function reason(opts)
    if opts.event == 'semantic_context_changed' then
        return 'semantic_context_changed'
    end

    if opts.event == 'WinScrolled' and opts.prior_cursor_row == opts.cursor_row then
        return 'explicit_scroll'
    end

    if opts.prior_cursor_row and math.abs(opts.cursor_row - opts.prior_cursor_row) == 1 then
        return 'linewise_cursor_motion'
    end

    if opts.prior_virtual_topline and opts.raw_topline == opts.prior_virtual_topline then
        return 'stable_viewport'
    end

    return 'explicit_jump'
end

---@param opts { cursor_row: integer, line_count: integer, winheight: integer, raw_topline: integer, current_physical_row?: integer, prior_cursor_row?: integer, prior_physical_row?: integer, prior_native_physical_row?: integer, effective_scrolloff?: integer, scrolloff?: integer, reason: string, wrap?: boolean }
---@return integer
local function projected_cursor_physical_row(opts)
    local scrolloff = math.max(0, opts.effective_scrolloff or opts.scrolloff or 0)
    local native_physical_row = opts.current_physical_row
        or clamp(opts.cursor_row - opts.raw_topline + 1, 1, opts.winheight)

    if
        opts.wrap
        or opts.reason ~= 'linewise_cursor_motion'
        or not opts.prior_cursor_row
        or not (opts.prior_native_physical_row or opts.prior_physical_row)
    then
        return clamp(native_physical_row, 1, opts.winheight)
    end

    local delta = opts.cursor_row - opts.prior_cursor_row
    local desired = (opts.prior_native_physical_row or opts.prior_physical_row) + delta
    local minimum = math.min(opts.cursor_row, scrolloff + 1)
    local rows_below = opts.line_count - opts.cursor_row
    local maximum = opts.winheight - math.min(scrolloff, rows_below)

    return clamp(desired, math.max(1, minimum), math.max(1, maximum))
end

---@param opts { cursor_row: integer, line_count: integer, winheight: integer, raw_topline: integer, current_physical_row?: integer, prior_cursor_row?: integer, prior_physical_row?: integer, prior_native_physical_row?: integer, prior_virtual_topline?: integer, user_scrolloff?: integer, effective_scrolloff?: integer, scrolloff?: integer, event?: string, candidates?: marginalia.ViewportCandidate[], wrap?: boolean }
---@return marginalia.ViewportProjection
function M.project(opts)
    local effective_scrolloff = math.max(0, opts.effective_scrolloff or opts.scrolloff or 0)
    local user_scrolloff = math.max(0, opts.user_scrolloff or effective_scrolloff)
    local projection_reason = reason(opts)
    local cursor_delta = opts.prior_cursor_row and opts.cursor_row - opts.prior_cursor_row or 0
    local native_linewise_scroll = projection_reason == 'linewise_cursor_motion'
        and opts.prior_virtual_topline ~= nil
        and opts.raw_topline - opts.prior_virtual_topline == cursor_delta
    local cursor_physical_row = projected_cursor_physical_row({
        cursor_row = opts.cursor_row,
        line_count = opts.line_count,
        winheight = opts.winheight,
        raw_topline = opts.raw_topline,
        current_physical_row = opts.current_physical_row,
        prior_cursor_row = opts.prior_cursor_row,
        prior_physical_row = opts.prior_physical_row,
        prior_native_physical_row = opts.prior_native_physical_row,
        effective_scrolloff = effective_scrolloff,
        reason = projection_reason,
        wrap = opts.wrap,
    })
    local context_capacity = math.min(math.max(0, cursor_physical_row - 1), math.max(0, opts.cursor_row - 1))

    if native_linewise_scroll then
        context_capacity = 0
    end

    local context_rows, selected_candidates, body_topline, body_botline = M.project_context_and_body({
        cursor_row = opts.cursor_row,
        line_count = opts.line_count,
        winheight = opts.winheight,
        cursor_physical_row = cursor_physical_row,
        context_capacity = context_capacity,
        candidates = opts.candidates or {},
    })
    local selected_frames = M.selected_frames(selected_candidates, context_rows)
    local visible_rows = copy_rows(context_rows)

    for row = body_topline, math.min(opts.cursor_row, body_botline) do
        visible_rows[#visible_rows + 1] = row
    end

    visible_rows = sorted_unique_rows(visible_rows)

    local conceal_start = math.min(body_topline, opts.cursor_row)

    if context_rows[1] then
        conceal_start = math.min(conceal_start, context_rows[1])
    end

    local actual_topline = context_rows[1] or body_topline

    return {
        reason = projection_reason,
        context_rows = context_rows,
        selected_candidates = selected_candidates,
        selected_frames = selected_frames,
        virtual_viewport = {
            topline = body_topline,
            botline = body_botline,
        },
        actual_viewport = {
            topline = actual_topline,
        },
        conceal_scope = {
            start_row = conceal_start,
            end_row = math.max(conceal_start, opts.cursor_row - 1),
        },
        visible_rows = visible_rows,
        cursor_physical_row = cursor_physical_row,
        scrolloff = {
            user = user_scrolloff,
            effective = effective_scrolloff,
        },
    }
end

return M
