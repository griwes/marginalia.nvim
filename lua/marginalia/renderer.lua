local M = {}

local namespace_prefix = 'marginalia'

---@param suffix? string
---@return integer
function M.namespace(suffix)
    if suffix and suffix ~= '' then
        return vim.api.nvim_create_namespace(namespace_prefix .. '.' .. suffix)
    end

    return vim.api.nvim_create_namespace(namespace_prefix)
end

---@param bufnr integer
---@param ns integer
function M.clear(bufnr, ns)
    if not vim.api.nvim_buf_is_valid(bufnr) then
        return
    end

    vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
end

---@param bufnr integer
---@param ns integer
---@param ranges marginalia.HiddenRange[]
---@param opts? { priority?: integer }
function M.apply(bufnr, ns, ranges, opts)
    opts = opts or {}

    if not vim.api.nvim_buf_is_valid(bufnr) then
        return
    end

    M.clear(bufnr, ns)

    for _, range in ipairs(ranges or {}) do
        if range.start_row <= range.end_row then
            vim.api.nvim_buf_set_extmark(bufnr, ns, range.start_row - 1, 0, {
                end_row = range.end_row - 1,
                end_col = -1,
                strict = false,
                conceal_lines = '',
                priority = opts.priority or 200,
            })
        end
    end
end

return M
