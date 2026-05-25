local M = {}

local ns = vim.api.nvim_create_namespace('marginalia.provider.conceal')
local installed = false

---@class marginalia.RenderProviderWindow
---@field bufnr integer
---@field hidden_ranges marginalia.HiddenRange[]
---@field priority integer
---@field checked table<integer, true>
---@field primed boolean?

---@type table<integer, marginalia.RenderProviderWindow>
local windows = {}

---@param bufnr integer
local function clear_buffer(bufnr)
    if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
    end
end

---@param bufnr integer
---@return boolean
local function buffer_is_not_shared_across_windows(bufnr)
    local count = 0

    for _, winid in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_is_valid(winid) and vim.api.nvim_win_get_buf(winid) == bufnr then
            count = count + 1

            if count > 1 then
                return false
            end
        end
    end

    return true
end

---@param range marginalia.HiddenRange
---@param row integer zero-based row
---@return boolean
local function range_contains_row(range, row)
    if range.start_row > range.end_row then
        return false
    end

    local one_based_row = row + 1

    return one_based_row >= range.start_row and one_based_row <= range.end_row
end

---@param entry marginalia.RenderProviderWindow
---@param row integer zero-based row
---@return marginalia.HiddenRange?
local function hidden_range_for_row(entry, row)
    for _, range in ipairs(entry.hidden_ranges) do
        if range_contains_row(range, row) then
            return range
        end
    end

    return nil
end

---@param entry marginalia.RenderProviderWindow
---@param row integer zero-based row
local function materialize_conceal(entry, row)
    local range = hidden_range_for_row(entry, row)

    if not range then
        return
    end

    vim.api.nvim_buf_set_extmark(entry.bufnr, ns, range.start_row - 1, 0, {
        end_row = range.end_row - 1,
        end_col = -1,
        strict = false,
        conceal_lines = '',
        priority = entry.priority,
    })
end

---@param entry marginalia.RenderProviderWindow
local function materialize_all(entry)
    for _, range in ipairs(entry.hidden_ranges) do
        materialize_conceal(entry, range.start_row - 1)

        for row = range.start_row - 1, range.end_row - 1 do
            entry.checked[row] = true
        end
    end
end

---@param _ string
---@param winid integer
---@param bufnr integer
---@param row integer
function M._on_conceal_line(_, winid, bufnr, row)
    local entry = windows[winid]

    if not entry or entry.bufnr ~= bufnr or entry.checked[row] then
        return
    end

    entry.checked[row] = true
    materialize_conceal(entry, row)
end

---@param _ string
---@param winid integer
---@param bufnr integer
---@return boolean
function M._on_win(_, winid, bufnr)
    local entry = windows[winid]

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

function M.install()
    if installed then
        return
    end

    vim.api.nvim_set_decoration_provider(ns, {
        on_win = M._on_win,
        _on_conceal_line = M._on_conceal_line,
    })
    installed = true
end

---@param state marginalia.WindowState
---@param ranges marginalia.HiddenRange[]
---@param opts? { priority?: integer, prime?: boolean }
function M.update_window(state, ranges, opts)
    M.install()
    opts = opts or {}

    clear_buffer(state.bufnr)

    windows[state.winid] = {
        bufnr = state.bufnr,
        hidden_ranges = vim.deepcopy(ranges or {}),
        priority = opts.priority or 200,
        checked = {},
        primed = false,
    }

    if opts.prime and buffer_is_not_shared_across_windows(state.bufnr) then
        materialize_all(windows[state.winid])
        windows[state.winid].primed = true
    end

    vim.api.nvim__redraw({ buf = state.bufnr, valid = false, flush = false })
end

---@param state marginalia.WindowState
function M.clear_window(state)
    windows[state.winid] = nil
    clear_buffer(state.bufnr)

    if state.identity and state.identity.bufnr and state.identity.bufnr ~= state.bufnr then
        clear_buffer(state.identity.bufnr)
    end
end

---@param winid integer
function M.remove_window(winid)
    local entry = windows[winid]

    if entry then
        clear_buffer(entry.bufnr)
    end

    windows[winid] = nil
end

---@param bufnr integer
function M.clear_buffer(bufnr)
    clear_buffer(bufnr)
end

---@return integer
function M.namespace()
    return ns
end

---@param winid integer
---@return table?
function M.debug_window(winid)
    local entry = windows[winid]

    if not entry then
        return nil
    end

    return {
        bufnr = entry.bufnr,
        hidden_ranges = vim.deepcopy(entry.hidden_ranges),
        priority = entry.priority,
        checked = vim.deepcopy(entry.checked),
    }
end

return M
