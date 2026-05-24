local config = require('marginalia.config')

local M = {}

---@param start_row integer
---@param start_col integer
---@param end_row integer
---@param end_col integer
---@return marginalia.FrameRange
function M.range_from_parts(start_row, start_col, end_row, end_col)
    return {
        start_row = start_row + 1,
        start_col = start_col,
        end_row = end_row + 1,
        end_col = end_col,
    }
end

---@param range integer[]
---@return marginalia.FrameRange
function M.range_from_zero_based(range)
    return M.range_from_parts(range[1], range[2], range[3], range[4])
end

---@param node TSNode
---@return marginalia.FrameRange
function M.node_range(node)
    return M.range_from_parts(node:range())
end

---@param range marginalia.FrameRange?
---@param fallback integer?
---@return integer?
function M.frame_start_row(range, fallback)
    if range and type(range.start_row) == 'number' then
        return range.start_row
    end

    return fallback
end

---@param range marginalia.FrameRange?
---@param fallback integer?
---@return integer?
function M.frame_end_row(range, fallback)
    if not range or type(range.end_row) ~= 'number' then
        return fallback
    end

    local end_row = range.end_row

    if range.end_col == 0 then
        end_row = end_row - 1
    end

    return math.max(range.start_row, end_row)
end

---@param frame marginalia.ContextFrame
---@return marginalia.ContextFrame
function M.copy_frame(frame)
    local copy = vim.tbl_extend('force', {}, frame)

    if frame.range then
        copy.range = vim.tbl_extend('force', {}, frame.range)
    end

    return copy
end

---@param frames marginalia.ContextFrame[]
---@return marginalia.ContextFrame[]
function M.copy_frames(frames)
    local result = {}

    for _, frame in ipairs(frames) do
        result[#result + 1] = M.copy_frame(frame)
    end

    return result
end

---@param frame marginalia.ContextFrame
---@return integer
function M.frame_height(frame)
    local start_row = M.frame_start_row(frame.range, frame.row)
    local end_row = M.frame_end_row(frame.range, start_row)

    if type(start_row) ~= 'number' or type(end_row) ~= 'number' then
        return 0
    end

    return math.max(0, end_row - start_row + 1)
end

---@param frame marginalia.ContextFrame
function M.truncate_frame_to_start_row(frame)
    local start_row = M.frame_start_row(frame.range, frame.row)

    if type(start_row) ~= 'number' then
        return
    end

    if frame.range then
        frame.range.end_row = start_row + 1
        frame.range.end_col = 0
    else
        frame.row = start_row
    end
end

---@class marginalia.FrameHeaderFacts
---@field row? integer
---@field end_row? integer
---@field multiline_function_header boolean
---@field cursor_on_struct_header boolean
---@field completed_struct_header boolean
---@field completed_function_header boolean
---@field in_progress_function_header boolean
---@field final_function_header_line boolean

---@param frame marginalia.ContextFrame
---@param capture string
---@return boolean
local function has_query_capture(frame, capture)
    return frame.query ~= nil and frame.query.captures ~= nil and frame.query.captures[capture] == true
end

---@param frame marginalia.ContextFrame
---@param capture string
---@return boolean
local function has_query_semantic(frame, capture)
    return has_query_capture(frame, capture)
end

---@param frame marginalia.ContextFrame
---@param cursor_row integer
---@param opts? { active_function_row?: integer, stitch?: { floor?: integer } }
---@return marginalia.FrameHeaderFacts
function M.frame_header_facts(frame, cursor_row, opts)
    opts = opts or {}

    local row = M.frame_start_row(frame.range, frame.row)
    local end_row = M.frame_end_row(frame.range, row)
    local has_header_rows = type(row) == 'number' and type(end_row) == 'number'
    local multiline_function_header = has_query_semantic(frame, 'context.header.function')
        and frame.range
        and frame.range.start_col > 0
    local struct_header = has_query_semantic(frame, 'context.header.struct')
    local active_function_row = opts.active_function_row
    local stitch = opts.stitch or {}
    local final_function_header_line = multiline_function_header
        and has_header_rows
        and cursor_row == end_row
        and stitch.floor
        and row >= stitch.floor
        and row ~= active_function_row

    return {
        row = row,
        end_row = end_row,
        multiline_function_header = multiline_function_header == true,
        cursor_on_struct_header = has_header_rows and struct_header and cursor_row <= end_row,
        completed_struct_header = has_header_rows and struct_header and cursor_row > end_row,
        completed_function_header = has_header_rows and multiline_function_header and cursor_row > end_row,
        in_progress_function_header = has_header_rows
            and multiline_function_header
            and cursor_row <= end_row
            and row ~= active_function_row,
        final_function_header_line = final_function_header_line == true,
    }
end

---@param frame marginalia.ContextFrame
---@param row integer?
---@param previous_row integer?
---@return boolean
function M.is_disconnected_compound_context(frame, row, previous_row)
    local compound_context = has_query_semantic(frame, 'context.body.compound')

    return compound_context and previous_row ~= nil and row ~= previous_row + 1
end

---@param frames marginalia.ContextFrame[]
---@param trim integer
function M.trim_outer_rows(frames, trim)
    while trim > 0 and #frames > 0 do
        local frame = frames[1]
        local height = M.frame_height(frame)
        local start_row = M.frame_start_row(frame.range, frame.row)
        local end_row = M.frame_end_row(frame.range, start_row)

        if height <= trim then
            table.remove(frames, 1)
            trim = trim - height
        else
            if frame.range then
                frame.range.end_row = end_row - trim + 1
                frame.range.end_col = 0
            else
                frame.row = end_row - trim
            end

            trim = 0
        end
    end
end

---@param frames marginalia.ContextFrame[]
---@return marginalia.ContextFrame[]
function M.renderable_frames(frames)
    local result = {}
    local seen = {}
    local previous_row

    for _, frame in ipairs(frames) do
        local row = frame.row or (frame.range and frame.range.start_row)

        if type(row) == 'number' then
            local skip_bare_compound = not seen[row] and M.is_disconnected_compound_context(frame, row, previous_row)

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
---@param cursor_row integer
---@return integer?
function M.nearest_start_row_before(frames, cursor_row)
    local nearest

    for _, frame in ipairs(M.renderable_frames(frames)) do
        local row = M.frame_start_row(frame.range, frame.row)

        if row and row < cursor_row and (not nearest or row > nearest) then
            nearest = row
        end
    end

    return nearest
end

---@param frames marginalia.ContextFrame[]
---@param row integer
---@return boolean
function M.has_start_row(frames, row)
    for _, frame in ipairs(M.renderable_frames(frames)) do
        if M.frame_start_row(frame.range, frame.row) == row then
            return true
        end
    end

    return false
end

---@param frames marginalia.ContextFrame[]
---@param row integer
---@return boolean
function M.has_start_row_at_or_after(frames, row)
    for _, frame in ipairs(M.renderable_frames(frames)) do
        local start_row = M.frame_start_row(frame.range, frame.row)

        if start_row and start_row >= row then
            return true
        end
    end

    return false
end

---@param frames marginalia.ContextFrame[]
---@param start_row integer
---@param end_row integer
---@return boolean
function M.has_start_row_in_range(frames, start_row, end_row)
    for _, frame in ipairs(M.renderable_frames(frames)) do
        local row = M.frame_start_row(frame.range, frame.row)

        if row and row >= start_row and row <= end_row then
            return true
        end
    end

    return false
end

---@class marginalia.ViewportCandidate
---@field frame marginalia.ContextFrame
---@field source_row integer
---@field end_row integer
---@field rows integer[]
---@field height integer
---@field outer_rank integer
---@field inner_rank integer
---@field frame_type string
---@field source 'query'|'ancestor'
---@field query? { captures: table<string, true> }

---@param frame marginalia.ContextFrame
---@param cursor_row integer
---@return integer[]
local function candidate_rows(frame, cursor_row)
    local start_row = M.frame_start_row(frame.range, frame.row)
    local end_row = M.frame_end_row(frame.range, start_row)
    local rows = {}

    if type(start_row) ~= 'number' or type(end_row) ~= 'number' then
        return rows
    end

    for row = start_row, math.min(end_row, cursor_row - 1) do
        rows[#rows + 1] = row
    end

    return rows
end

---@param frames marginalia.ContextFrame[]
---@param cursor_row integer
---@return marginalia.ViewportCandidate[]
function M.candidates(frames, cursor_row)
    local candidates = {}

    for index, frame in ipairs(frames or {}) do
        local rows = candidate_rows(frame, cursor_row)

        if #rows > 0 then
            candidates[#candidates + 1] = {
                frame = frame,
                source_row = rows[1],
                end_row = rows[#rows],
                rows = rows,
                height = #rows,
                outer_rank = index,
                inner_rank = #frames - index + 1,
                frame_type = frame.type,
                source = frame.source or 'ancestor',
                query = frame.query,
            }
        end
    end

    return candidates
end

---@param frames marginalia.ContextFrame[]
---@param max_depth integer
---@return marginalia.ContextFrame[]
function M.apply_depth_limit(frames, max_depth)
    if max_depth == 0 or #frames <= max_depth then
        return frames
    end

    local limited = {}
    local first = #frames - max_depth + 1

    for index = first, #frames do
        limited[#limited + 1] = frames[index]
    end

    for index, frame in ipairs(limited) do
        frame.depth = index
    end

    return limited
end

---@param frames marginalia.ContextFrame[]
---@param opts? marginalia.Config
---@return marginalia.ContextFrame[]
function M.frames(frames, opts)
    local resolved = config.normalize(opts)
    local normalized = M.apply_depth_limit(frames, resolved.context.max_depth)

    for index, frame in ipairs(normalized) do
        frame.depth = index
    end

    return normalized
end

return M
