local config = require('marginalia.config')

local M = {}

---@class marginalia.FrameRange
---@field start_row integer
---@field start_col integer
---@field end_row integer
---@field end_col integer

---@class marginalia.ContextFrame
---@field type string
---@field depth integer
---@field range marginalia.FrameRange
---@field row integer

---@class marginalia.ContextResult
---@field frames marginalia.ContextFrame[]
---@field reason? string

---@param node any
---@return boolean
local function is_named(node)
    if not node or type(node.named) ~= 'function' then
        return true
    end

    return node:named()
end

---@param node any
---@return marginalia.FrameRange
local function node_range(node)
    local start_row, start_col, end_row, end_col = node:range()

    return {
        start_row = start_row + 1,
        start_col = start_col,
        end_row = end_row + 1,
        end_col = end_col,
    }
end

---@param node any
---@param depth integer
---@return marginalia.ContextFrame
local function frame_from_node(node, depth)
    local range = node_range(node)

    return {
        type = node:type(),
        depth = depth,
        range = range,
        row = range.start_row,
    }
end

---@param node any
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

---@param node any
---@param row integer
---@param col integer
---@return any
local function innermost_named_node_at(node, row, col)
    if not node or not contains_position(node, row, col) then
        return nil
    end

    if type(node.iter_children) ~= 'function' then
        return is_named(node) and node or nil
    end

    for child in node:iter_children() do
        if is_named(child) and contains_position(child, row, col) then
            return innermost_named_node_at(child, row, col) or child
        end
    end

    return is_named(node) and node or nil
end

---@param frames marginalia.ContextFrame[]
---@param max_depth integer
---@return marginalia.ContextFrame[]
local function apply_depth_limit(frames, max_depth)
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

---@param node any
---@param opts? marginalia.Config
---@return marginalia.ContextFrame[]
function M.collect_ancestors(node, opts)
    if not node then
        return {}
    end

    local resolved = config.normalize(opts)
    local frames = {}
    local current = node

    while current do
        local node_type = current:type()

        if is_named(current) and not resolved.skip_node_types[node_type] then
            frames[#frames + 1] = frame_from_node(current, 0)
        end

        current = type(current.parent) == 'function' and current:parent() or nil
    end

    local ordered = {}

    for index = #frames, 1, -1 do
        ordered[#ordered + 1] = frames[index]
    end

    ordered = apply_depth_limit(ordered, resolved.max_depth)

    for index, frame in ipairs(ordered) do
        frame.depth = index
    end

    return ordered
end

---@param opts? { bufnr?: integer, winid?: integer, lang?: string, max_depth?: integer, skip_node_types?: string[]|table<string, boolean> }
---@return marginalia.ContextResult
function M.for_window(opts)
    opts = opts or {}

    local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
    local winid = opts.winid or vim.api.nvim_get_current_win()
    local cursor = vim.api.nvim_win_get_cursor(winid)
    local row = cursor[1] - 1
    local col = cursor[2]

    local parser_ok, parser = pcall(vim.treesitter.get_parser, bufnr, opts.lang)

    if not parser_ok or not parser then
        return { frames = {}, reason = 'no_parser' }
    end

    local parse_ok, trees = pcall(function()
        return parser:parse()
    end)

    if not parse_ok or not trees or not trees[1] then
        return { frames = {}, reason = 'parse_failed' }
    end

    local root = trees[1]:root()
    local node = innermost_named_node_at(root, row, col)

    return { frames = M.collect_ancestors(node, opts) }
end

return M
