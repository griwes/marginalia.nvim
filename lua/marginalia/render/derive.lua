local M = {}

---@class marginalia.HiddenRange
---@field start_row integer
---@field end_row integer

---@param rows integer[]|table<integer, boolean>|nil
---@return table<integer, boolean>, integer
function M.normalize_row_set(rows)
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
function M.include_row(set, row)
    if type(row) ~= 'number' or row <= 0 or set[row] then
        return 0
    end

    set[row] = true
    return 1
end

---@param rows table<integer, boolean>
---@return integer[]
function M.sorted_rows(rows)
    local result = {}

    for row in pairs(rows) do
        result[#result + 1] = row
    end

    table.sort(result)

    return result
end

---@param opts { visible_rows?: integer[]|table<integer, boolean>, conceal_start_row?: integer, conceal_end_row?: integer }
---@return marginalia.HiddenRange[]
function M.hidden_ranges(opts)
    opts = opts or {}

    local start_row = opts.conceal_start_row or 1
    local end_row = opts.conceal_end_row or 0
    local visible, visible_count = M.normalize_row_set(opts.visible_rows)

    if start_row > end_row or visible_count == 0 then
        return {}
    end

    local ranges = {}
    local active_start = nil

    for row = start_row, end_row do
        if visible[row] then
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

---@param projection { visible_rows: integer[]|table<integer, boolean>, conceal_scope: { start_row: integer, end_row: integer } }
---@return { visible_rows: integer[], hidden_ranges: marginalia.HiddenRange[] }
function M.from_projection(projection)
    local visible_rows = M.sorted_rows(M.normalize_row_set(projection.visible_rows))

    return {
        visible_rows = visible_rows,
        hidden_ranges = M.hidden_ranges({
            conceal_start_row = projection.conceal_scope.start_row,
            conceal_end_row = projection.conceal_scope.end_row,
            visible_rows = visible_rows,
        }),
    }
end

return M
