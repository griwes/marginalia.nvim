local M = {}

---@class marginalia.HiddenRange
---@field start_row integer
---@field end_row integer

---@param rows integer[]|table<integer, boolean>|nil
---@return table<integer, boolean>, integer
local function normalize_row_set(rows)
    local result = {}
    local count = 0

    for key, value in pairs(rows or {}) do
        local row = key

        if type(key) == 'number' and type(value) ~= 'boolean' then
            row = value
        end

        if type(key) ~= 'number' or value ~= false then
            if type(row) == 'number' and row > 0 and not result[row] then
                result[row] = true
                count = count + 1
            end
        end
    end

    return result, count
end

---@param set table<integer, boolean>
---@param row integer?
---@return integer
local function protect_row(set, row)
    if type(row) ~= 'number' or row <= 0 or set[row] then
        return 0
    end

    set[row] = true
    return 1
end

---@param rows table<integer, boolean>
---@return integer[]
local function sorted_rows(rows)
    local result = {}

    for row in pairs(rows) do
        result[#result + 1] = row
    end

    table.sort(result)

    return result
end

---@class marginalia.ProtectedRange
---@field start_row integer
---@field end_row integer

---@param set table<integer, boolean>
---@param start_row integer?
---@param end_row integer?
local function protect_range(set, start_row, end_row)
    if type(start_row) ~= 'number' or type(end_row) ~= 'number' then
        return
    end

    for row = math.max(1, start_row), math.max(start_row, end_row) do
        protect_row(set, row)
    end
end

---@param opts { frames?: marginalia.ContextFrame[], cursor_row?: integer, protected_rows?: integer[]|table<integer, boolean>, protected_ranges?: marginalia.ProtectedRange[] }
---@return integer[]
function M.protected_rows(opts)
    opts = opts or {}

    local rows = normalize_row_set(opts.protected_rows)

    for _, frame in ipairs(opts.frames or {}) do
        protect_row(rows, frame.row or (frame.range and frame.range.start_row))
    end

    protect_row(rows, opts.cursor_row)

    for _, range in ipairs(opts.protected_ranges or {}) do
        protect_range(rows, range.start_row, range.end_row)
    end

    return sorted_rows(rows)
end

---@param opts { start_row?: integer, end_row?: integer, protected_rows?: integer[]|table<integer, boolean> }
---@return marginalia.HiddenRange[]
function M.hidden_ranges(opts)
    opts = opts or {}

    local start_row = opts.start_row or 1
    local end_row = opts.end_row or 0
    local protected, protected_count = normalize_row_set(opts.protected_rows)

    if start_row > end_row or protected_count == 0 then
        return {}
    end

    local ranges = {}
    local active_start = nil

    for row = start_row, end_row do
        if protected[row] then
            if active_start then
                ranges[#ranges + 1] = { start_row = active_start, end_row = row - 1 }
                active_start = nil
            end
        elseif not active_start then
            active_start = row
        end
    end

    if active_start then
        ranges[#ranges + 1] = { start_row = active_start, end_row = end_row }
    end

    return ranges
end

---@param opts { frames?: marginalia.ContextFrame[], cursor_row?: integer, protected_rows?: integer[]|table<integer, boolean>, protected_ranges?: marginalia.ProtectedRange[], start_row?: integer, end_row?: integer }
---@return { protected_rows: integer[], hidden_ranges: marginalia.HiddenRange[] }
function M.plan(opts)
    opts = opts or {}

    local protected_rows = M.protected_rows(opts)
    local hidden_ranges = M.hidden_ranges({
        start_row = opts.start_row,
        end_row = opts.end_row,
        protected_rows = protected_rows,
    })

    return {
        protected_rows = protected_rows,
        hidden_ranges = hidden_ranges,
    }
end

return M
