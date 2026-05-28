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

---@alias marginalia.RowHeightProvider fun(row: integer): integer

---@param provider? table<integer, integer>|marginalia.RowHeightProvider
---@return marginalia.RowHeightProvider
local function row_height_provider(provider)
    if type(provider) == 'function' then
        return function(row)
            local ok, height = pcall(provider, row)

            if ok and type(height) == 'number' and height > 0 then
                return math.max(1, math.floor(height))
            end

            return 1
        end
    end

    if type(provider) == 'table' then
        return function(row)
            local height = provider[row]

            if type(height) == 'number' and height > 0 then
                return math.max(1, math.floor(height))
            end

            return 1
        end
    end

    return function()
        return 1
    end
end

---@param rows integer[]
---@param row_height marginalia.RowHeightProvider
---@return integer
local function rows_physical_height(rows, row_height)
    local height = 0

    for _, row in ipairs(rows) do
        height = height + row_height(row)
    end

    return height
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
---@param row_height? marginalia.RowHeightProvider
---@return integer[], marginalia.ViewportCandidate[]
function M.allocate_context_rows(candidates, capacity, row_height)
    capacity = math.max(0, capacity or 0)
    row_height = row_height or row_height_provider()

    if capacity == 0 then
        return {}, {}
    end

    local selected_rows = {}
    local selected_candidates = {}
    local remaining = capacity

    for index = #candidates, 1, -1 do
        local candidate = candidates[index]
        local candidate_height = rows_physical_height(candidate.rows or {}, row_height)

        if candidate_height <= remaining then
            table.insert(selected_candidates, 1, candidate)

            for row_index = #candidate.rows, 1, -1 do
                table.insert(selected_rows, 1, candidate.rows[row_index])
            end

            remaining = remaining - candidate_height
        elseif #selected_candidates == 0 and remaining > 0 then
            local used = 0
            local rows = {}

            for _, row in ipairs(candidate.rows or {}) do
                local height = row_height(row)

                if used + height > remaining then
                    break
                end

                rows[#rows + 1] = row
                used = used + height
            end

            if #rows > 0 then
                table.insert(selected_candidates, 1, candidate)

                for row_index = #rows, 1, -1 do
                    table.insert(selected_rows, 1, rows[row_index])
                end
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

---@param a integer[]
---@param b integer[]
---@return boolean
local function rows_equal(a, b)
    if #a ~= #b then
        return false
    end

    for index, row in ipairs(a) do
        if b[index] ~= row then
            return false
        end
    end

    return true
end

---@param cursor_row integer
---@param capacity integer
---@param row_height marginalia.RowHeightProvider
---@return integer
local function body_topline_for_capacity(cursor_row, capacity, row_height)
    capacity = math.max(0, capacity)

    local used = 0
    local topline = cursor_row

    for row = cursor_row - 1, 1, -1 do
        local height = row_height(row)

        if used + height > capacity then
            break
        end

        used = used + height
        topline = row
    end

    return topline
end

---@param topline integer
---@param line_count integer
---@param capacity integer
---@param row_height marginalia.RowHeightProvider
---@return integer
local function body_botline_for_capacity(topline, line_count, capacity, row_height)
    capacity = math.max(1, capacity)

    local used = 0
    local botline = topline

    for row = topline, line_count do
        local height = row_height(row)

        if used > 0 and used + height > capacity then
            break
        end

        used = used + height
        botline = row
    end

    return botline
end

---@param start_row integer
---@param end_row integer
---@param row_height marginalia.RowHeightProvider
---@return integer
local function range_physical_height(start_row, end_row, row_height)
    if end_row < start_row then
        return 0
    end

    local height = 0

    for row = start_row, end_row do
        height = height + row_height(row)
    end

    return height
end

---@param opts { cursor_row: integer, line_count: integer, winheight: integer, cursor_physical_row: integer, candidates: marginalia.ViewportCandidate[], context_capacity: integer, row_height?: table<integer, integer>|marginalia.RowHeightProvider }
---@return integer[], marginalia.ViewportCandidate[], integer, integer
function M.project_context_and_body(opts)
    local row_height = row_height_provider(opts.row_height)
    local context_rows = {}
    local selected_candidates = {}
    local body_topline = body_topline_for_capacity(opts.cursor_row, opts.cursor_physical_row - 1, row_height)
    local body_botline = opts.cursor_row
    local max_iterations = math.max(1, (opts.context_capacity or 0) + #(opts.candidates or {}) + 2)

    for _ = 1, max_iterations do
        local context_height = rows_physical_height(context_rows, row_height)
        local body_capacity_above_cursor = math.max(0, opts.cursor_physical_row - context_height - 1)
        local next_body_topline = body_topline_for_capacity(opts.cursor_row, body_capacity_above_cursor, row_height)
        local body_capacity = math.max(1, opts.winheight - context_height)
        local next_body_botline =
            body_botline_for_capacity(next_body_topline, opts.line_count, body_capacity, row_height)
        local pinned_candidates = M.candidates_above_virtual_viewport(opts.candidates, next_body_topline)
        local next_context_rows, next_selected_candidates =
            M.allocate_context_rows(pinned_candidates, opts.context_capacity, row_height)

        if rows_equal(next_context_rows, context_rows) and next_body_topline == body_topline then
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

---@param opts { cursor_row: integer, line_count: integer, winheight: integer, raw_topline: integer, current_physical_row?: integer, prior_cursor_row?: integer, prior_physical_row?: integer, prior_raw_topline?: integer, prior_virtual_topline?: integer, logical_scroll_delta?: integer, effective_scrolloff?: integer, scrolloff?: integer, event?: string, candidates?: marginalia.ViewportCandidate[], row_height?: table<integer, integer>|marginalia.RowHeightProvider }
---@return string
local function reason(opts)
    if opts.event == 'MouseScrolled' and opts.logical_scroll_delta then
        return 'logical_scroll'
    end

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

---@param opts { cursor_row: integer, line_count: integer, winheight: integer, prior_virtual_topline?: integer, raw_topline: integer, logical_scroll_delta: integer, candidates: marginalia.ViewportCandidate[], row_height?: table<integer, integer>|marginalia.RowHeightProvider }
---@return integer[], marginalia.ViewportCandidate[], integer, integer, integer
local function project_logical_scroll(opts)
    local row_height = row_height_provider(opts.row_height)
    local prior_topline = opts.prior_virtual_topline or opts.raw_topline
    local body_topline = clamp(prior_topline + opts.logical_scroll_delta, 1, opts.cursor_row)
    local body_above_cursor_height = range_physical_height(body_topline, opts.cursor_row - 1, row_height)

    while body_topline < opts.cursor_row and body_above_cursor_height + row_height(opts.cursor_row) > opts.winheight do
        body_above_cursor_height = body_above_cursor_height - row_height(body_topline)
        body_topline = body_topline + 1
    end

    local context_capacity = math.min(
        math.max(0, opts.winheight - body_above_cursor_height - row_height(opts.cursor_row)),
        math.max(0, opts.cursor_row - 1)
    )
    local pinned_candidates = M.candidates_above_virtual_viewport(opts.candidates, body_topline)
    local context_rows, selected_candidates = M.allocate_context_rows(pinned_candidates, context_capacity, row_height)
    local context_height = rows_physical_height(context_rows, row_height)
    local body_capacity = math.max(1, opts.winheight - context_height)
    local body_botline = body_botline_for_capacity(body_topline, opts.line_count, body_capacity, row_height)
    local cursor_physical_row = context_height + body_above_cursor_height + 1

    return context_rows, selected_candidates, body_topline, body_botline, cursor_physical_row
end

---@param opts { cursor_row: integer, line_count: integer, winheight: integer, raw_topline: integer, current_physical_row?: integer, prior_cursor_row?: integer, prior_physical_row?: integer, prior_native_physical_row?: integer, forced_cursor_physical_row?: integer, effective_scrolloff?: integer, scrolloff?: integer, reason: string, wrap?: boolean }
---@return integer
local function projected_cursor_physical_row(opts)
    local scrolloff = math.max(0, opts.effective_scrolloff or opts.scrolloff or 0)
    local native_physical_row = opts.current_physical_row
        or clamp(opts.cursor_row - opts.raw_topline + 1, 1, opts.winheight)

    if opts.forced_cursor_physical_row then
        return clamp(opts.forced_cursor_physical_row, 1, opts.winheight)
    end

    if opts.reason == 'explicit_scroll' and opts.prior_cursor_row == opts.cursor_row and opts.prior_physical_row then
        return clamp(opts.prior_physical_row, 1, opts.winheight)
    end

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

---@param opts { cursor_row: integer, line_count: integer, winheight: integer, raw_topline: integer, current_physical_row?: integer, prior_cursor_row?: integer, prior_physical_row?: integer, prior_native_physical_row?: integer, prior_raw_topline?: integer, prior_virtual_topline?: integer, logical_scroll_delta?: integer, forced_cursor_physical_row?: integer, user_scrolloff?: integer, effective_scrolloff?: integer, scrolloff?: integer, event?: string, candidates?: marginalia.ViewportCandidate[], wrap?: boolean, row_height?: table<integer, integer>|marginalia.RowHeightProvider }
---@return marginalia.ViewportProjection
function M.project(opts)
    local effective_scrolloff = math.max(0, opts.effective_scrolloff or opts.scrolloff or 0)
    local user_scrolloff = math.max(0, opts.user_scrolloff or effective_scrolloff)
    local projection_reason = reason(opts)
    local cursor_physical_row
    local context_rows
    local selected_candidates
    local body_topline
    local body_botline

    local explicit_scroll_delta = nil

    if
        projection_reason == 'explicit_scroll'
        and opts.prior_virtual_topline
        and opts.prior_raw_topline
        and opts.raw_topline ~= opts.prior_raw_topline
    then
        explicit_scroll_delta = opts.raw_topline - opts.prior_raw_topline
    end

    if projection_reason == 'logical_scroll' or explicit_scroll_delta then
        context_rows, selected_candidates, body_topline, body_botline, cursor_physical_row = project_logical_scroll({
            cursor_row = opts.cursor_row,
            line_count = opts.line_count,
            winheight = opts.winheight,
            raw_topline = opts.raw_topline,
            prior_virtual_topline = opts.prior_virtual_topline,
            logical_scroll_delta = explicit_scroll_delta or opts.logical_scroll_delta or 0,
            candidates = opts.candidates or {},
            row_height = opts.row_height,
        })
    else
        cursor_physical_row = projected_cursor_physical_row({
            cursor_row = opts.cursor_row,
            line_count = opts.line_count,
            winheight = opts.winheight,
            raw_topline = opts.raw_topline,
            current_physical_row = opts.current_physical_row,
            prior_cursor_row = opts.prior_cursor_row,
            prior_physical_row = opts.prior_physical_row,
            prior_native_physical_row = opts.prior_native_physical_row,
            forced_cursor_physical_row = opts.forced_cursor_physical_row,
            effective_scrolloff = effective_scrolloff,
            reason = projection_reason,
            wrap = opts.wrap,
        })

        local context_capacity = math.min(math.max(0, cursor_physical_row - 1), math.max(0, opts.cursor_row - 1))

        context_rows, selected_candidates, body_topline, body_botline = M.project_context_and_body({
            cursor_row = opts.cursor_row,
            line_count = opts.line_count,
            winheight = opts.winheight,
            cursor_physical_row = cursor_physical_row,
            context_capacity = context_capacity,
            candidates = opts.candidates or {},
            row_height = opts.row_height,
        })
    end

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
