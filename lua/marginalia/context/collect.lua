local config = require('marginalia.config')
local normalize = require('marginalia.context.normalize')

local M = {}

---@class marginalia.ContextQuery
---@field captures string[]
---@field iter_matches fun(self: marginalia.ContextQuery, node: TSNode, source: integer, start?: integer, stop?: integer, opts?: table): any

---@param node TSNode?
---@return boolean
local function is_named(node)
    if not node or type(node.named) ~= 'function' then
        return true
    end

    return node:named()
end

---@param node TSNode
---@return boolean
local function is_single_line(node)
    local start_row, _, end_row = node:range()

    return start_row == end_row
end

---@param bufnr integer
---@param range integer[]
---@return integer[]
local function trim_context_query_range(bufnr, range)
    if type(bufnr) ~= 'number' or bufnr <= 0 or not vim.api.nvim_buf_is_valid(bufnr) then
        return range
    end

    local start_row = range[1]
    local start_col = range[2]
    local end_row = range[3]
    local end_col = range[4]

    if type(start_row) ~= 'number' or type(end_row) ~= 'number' or end_row <= start_row then
        return range
    end

    local text_end_row = end_row
    local inspect_col = end_col

    if end_col == 0 then
        text_end_row = end_row - 1
        inspect_col = -1
    end

    if text_end_row < start_row then
        return range
    end

    local ok, lines = pcall(vim.api.nvim_buf_get_text, bufnr, start_row, 0, text_end_row, -1, {})

    if not ok or #lines == 0 then
        return range
    end

    while #lines > 0 do
        local line = lines[#lines]
        local inspected = inspect_col >= 0 and line:sub(1, inspect_col) or line

        if inspected:match('%S') then
            break
        end

        lines[#lines] = nil
        text_end_row = text_end_row - 1
        inspect_col = -1
    end

    if #lines == 0 then
        return { start_row, start_col, start_row + 1, 0 }
    end

    if inspect_col ~= 0 then
        return { start_row, start_col, text_end_row + 1, 0 }
    end

    return { start_row, start_col, text_end_row, inspect_col }
end

---@param node TSNode
---@param depth integer
---@return marginalia.ContextFrame
local function frame_from_node(node, depth)
    local range = normalize.node_range(node)

    return {
        type = node:type(),
        depth = depth,
        range = range,
        row = range.start_row,
    }
end

---@param node TSNode
---@param depth integer
---@param range integer[]
---@param metadata? { captures: table<string, true> }
---@return marginalia.ContextFrame
local function frame_from_query_range(node, depth, range, metadata)
    local resolved_range = normalize.range_from_zero_based(range)

    return {
        type = node:type(),
        depth = depth,
        range = resolved_range,
        row = resolved_range.start_row,
        source = 'query',
        query = metadata,
    }
end

---@param nodes TSNode|TSNode[]
---@return TSNode?
local function last_capture_node(nodes)
    if type(nodes) == 'table' and type(nodes.range) ~= 'function' then
        return nodes[#nodes]
    end

    return nodes
end

---@param node TSNode
---@param bufnr integer
---@param query marginalia.ContextQuery?
---@return integer[]?, { captures: table<string, true> }?
local function context_query_range(node, bufnr, query)
    if not query or type(query.iter_matches) ~= 'function' then
        return nil
    end

    local start_row, start_col = node:range()
    local range = { start_row, start_col, start_row + 1, 0 }
    local is_context = false
    local metadata = { captures = {} }

    for _, match in query:iter_matches(node, bufnr, 0, -1, { max_start_depth = 0 }) do
        for id, nodes in pairs(match) do
            local capture_node = last_capture_node(nodes)
            local name = query.captures and query.captures[id]

            if capture_node and name then
                metadata.captures[name] = true

                local capture_start_row, capture_start_col, capture_end_row, capture_end_col = capture_node:range()

                if name == 'context' then
                    is_context = is_context or capture_node == node
                elseif name == 'context.start' then
                    range[1] = capture_start_row
                    range[2] = capture_start_col
                elseif name == 'context.final' then
                    range[3] = capture_end_row
                    range[4] = capture_end_col
                elseif name == 'context.end' then
                    range[3] = capture_start_row
                    range[4] = capture_start_col
                end
            end
        end

        if is_context then
            return trim_context_query_range(bufnr, range), metadata
        end
    end

    return nil
end

---@param node TSNode
---@param row integer
---@param col integer
---@return boolean
local function contains_position(node, row, col)
    local start_row, start_col, end_row, end_col = node:range()

    if row < start_row or row > end_row then
        return false
    end

    if row == start_row and col < start_col then
        return false
    end

    if row == end_row and col >= end_col then
        return false
    end

    return true
end

---@param node TSNode?
---@param row integer
---@param col integer
---@return TSNode?
function M.innermost_named_node_at(node, row, col)
    if not node or not contains_position(node, row, col) then
        return nil
    end

    if type(node.iter_children) ~= 'function' then
        return is_named(node) and node or nil
    end

    for child in node:iter_children() do
        if is_named(child) and contains_position(child, row, col) then
            return M.innermost_named_node_at(child, row, col) or child
        end
    end

    return is_named(node) and node or nil
end

---@param node TSNode?
---@param opts? marginalia.Config|{ bufnr?: integer, context_query?: marginalia.ContextQuery }
---@return marginalia.ContextFrame[]
function M.ancestors(node, opts)
    if not node then
        return {}
    end

    local resolved = config.normalize(opts)
    local frames = {}
    local current = node
    local query = opts and opts.context_query or nil
    local bufnr = opts and opts.bufnr or 0

    while current do
        local node_type = current:type()
        local query_range, query_metadata = nil, nil

        if query then
            query_range, query_metadata = context_query_range(current, bufnr, query)
        end

        if query_range then
            frames[#frames + 1] = frame_from_query_range(current, 0, query_range, query_metadata)
        elseif
            not query
            and is_named(current)
            and not resolved.context.skip_node_types[node_type]
            and not is_single_line(current)
        then
            frames[#frames + 1] = frame_from_node(current, 0)
        end

        current = type(current.parent) == 'function' and current:parent() or nil
    end

    local ordered = {}

    for index = #frames, 1, -1 do
        ordered[#ordered + 1] = frames[index]
    end

    return ordered
end

return M
