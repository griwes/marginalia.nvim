local M = {}

---@class marginalia.RenderCompatibilityProvider
---@field namespace fun(): integer
---@field supported fun(): boolean
---@field install fun()
---@field prime fun(entry: marginalia.RenderProviderWindow): boolean

---@param entry_for_win fun(winid: integer): marginalia.RenderProviderWindow?
---@return marginalia.RenderCompatibilityProvider
function M.new(entry_for_win)
    local ns = vim.api.nvim_create_namespace('marginalia.provider.conceal')
    local installed = false

    ---@param bufnr integer
    local function clear_buffer(bufnr)
        if vim.api.nvim_buf_is_valid(bufnr) then
            vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
        end
    end

    ---@param entry marginalia.RenderProviderWindow
    ---@param range marginalia.HiddenRange
    local function materialize_range(entry, range)
        if range.start_row > range.end_row then
            return
        end

        local end_row = range.end_row - 1
        local end_line = vim.api.nvim_buf_get_lines(entry.bufnr, end_row, end_row + 1, true)[1] or ''

        vim.api.nvim_buf_set_extmark(entry.bufnr, ns, range.start_row - 1, 0, {
            end_row = end_row,
            end_col = #end_line,
            strict = false,
            conceal_lines = '',
            priority = entry.priority,
        })
    end

    ---@param range marginalia.HiddenRange
    ---@param row integer
    ---@return boolean
    local function range_contains_row(range, row)
        local one_based_row = row + 1
        return one_based_row >= range.start_row and one_based_row <= range.end_row
    end

    ---@param entry marginalia.RenderProviderWindow
    local function materialize_all(entry)
        clear_buffer(entry.bufnr)
        entry.checked = {}

        for _, range in ipairs(entry.hidden_ranges) do
            materialize_range(entry, range)

            for row = range.start_row - 1, range.end_row - 1 do
                entry.checked[row] = true
            end
        end
    end

    ---@param bufnr integer
    ---@return boolean
    local function buffer_is_shared(bufnr)
        local count = 0

        for _, winid in ipairs(vim.api.nvim_list_wins()) do
            if vim.api.nvim_win_is_valid(winid) and vim.api.nvim_win_get_buf(winid) == bufnr then
                count = count + 1

                if count > 1 then
                    return true
                end
            end
        end

        return false
    end

    ---@param _ string
    ---@param winid integer
    ---@param bufnr integer
    ---@return boolean
    local function on_win(_, winid, bufnr)
        local entry = entry_for_win(winid)

        if not entry or entry.bufnr ~= bufnr or #entry.hidden_ranges == 0 then
            clear_buffer(bufnr)
            return false
        end

        if entry.primed then
            entry.primed = false
            return true
        end

        clear_buffer(bufnr)
        entry.checked = {}
        return true
    end

    ---@param _ string
    ---@param winid integer
    ---@param bufnr integer
    ---@param row integer
    local function on_conceal_line(_, winid, bufnr, row)
        local entry = entry_for_win(winid)

        if not entry or entry.bufnr ~= bufnr or entry.checked[row] then
            return
        end

        for _, range in ipairs(entry.hidden_ranges) do
            if range_contains_row(range, row) then
                materialize_range(entry, range)

                for checked_row = range.start_row - 1, range.end_row - 1 do
                    entry.checked[checked_row] = true
                end

                return
            end
        end
    end

    local provider = {}

    function provider.namespace()
        return ns
    end

    function provider.supported()
        return type(vim.api.nvim_set_decoration_provider) == 'function'
    end

    function provider.install()
        if installed then
            return
        end

        vim.api.nvim_set_decoration_provider(ns, {
            on_win = on_win,
            _on_conceal_line = on_conceal_line,
        })
        installed = true
    end

    function provider.prime(entry)
        if buffer_is_shared(entry.bufnr) then
            return false
        end

        materialize_all(entry)
        entry.primed = true
        return true
    end

    return provider
end

return M
