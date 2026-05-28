local M = {}

local fallback_ns = vim.api.nvim_create_namespace('marginalia.provider.conceal')

---@class marginalia.RenderProviderWindow
---@field bufnr integer
---@field ns integer
---@field hidden_ranges marginalia.HiddenRange[]
---@field priority integer
---@field checked table<integer, true>
---@field primed boolean?

---@type table<integer, marginalia.RenderProviderWindow>
local windows = {}

local unsupported_reason = 'nvim__ns_set is unavailable; per-window conceal is disabled'

---@param winid integer
---@return boolean
local function valid_win(winid)
    return type(winid) == 'number' and vim.api.nvim_win_is_valid(winid)
end

---@param state marginalia.WindowState|table
---@return integer
local function namespace_for_state(state)
    if type(state.ns) == 'number' then
        return state.ns
    end

    local entry = windows[state.winid]

    if entry and entry.ns then
        return entry.ns
    end

    return vim.api.nvim_create_namespace('marginalia.provider.conceal.win.' .. tostring(state.winid))
end

---@return boolean, string?
function M.supported()
    if type(vim.api.nvim__ns_set) ~= 'function' then
        return false, unsupported_reason
    end

    return true, nil
end

---@param ns integer
---@param winid integer
---@return boolean
local function scope_namespace(ns, winid)
    if not valid_win(winid) then
        return false
    end

    vim.api.nvim__ns_set(ns, { wins = { winid } })
    return true
end

---@param bufnr integer
---@param ns integer
local function clear_namespace(bufnr, ns)
    if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
    end
end

---@param bufnr integer
---@param ns integer
---@param range marginalia.HiddenRange
---@param priority integer
local function materialize_range(bufnr, ns, range, priority)
    if range.start_row > range.end_row then
        return
    end

    vim.api.nvim_buf_set_extmark(bufnr, ns, range.start_row - 1, 0, {
        end_row = range.end_row - 1,
        end_col = -1,
        strict = false,
        conceal_lines = '',
        priority = priority,
    })
end

---@param entry marginalia.RenderProviderWindow
local function materialize_all(entry)
    clear_namespace(entry.bufnr, entry.ns)
    entry.checked = {}

    for _, range in ipairs(entry.hidden_ranges) do
        materialize_range(entry.bufnr, entry.ns, range, entry.priority)

        for row = range.start_row - 1, range.end_row - 1 do
            entry.checked[row] = true
        end
    end
end

---@return boolean, string?
function M.install()
    local supported, reason = M.supported()

    if not supported then
        local notify = vim.notify_once or vim.notify

        notify(reason, vim.log.levels.ERROR, { title = 'marginalia.nvim' })
        return false, reason
    end

    return true, nil
end

---@param state marginalia.WindowState
---@param ranges marginalia.HiddenRange[]
---@param opts? { priority?: integer, prime?: boolean }
---@return boolean, string?
function M.update_window(state, ranges, opts)
    local supported, reason = M.install()

    if not supported then
        local previous = windows[state.winid]

        if previous then
            clear_namespace(previous.bufnr, previous.ns)
        end

        clear_namespace(state.bufnr, namespace_for_state(state))
        windows[state.winid] = nil
        return false, reason
    end

    opts = opts or {}

    local ns = namespace_for_state(state)
    local previous = windows[state.winid]

    if previous then
        clear_namespace(previous.bufnr, previous.ns)
    end

    if not scope_namespace(ns, state.winid) then
        clear_namespace(state.bufnr, ns)
        windows[state.winid] = nil
        return false, 'invalid_window'
    end

    windows[state.winid] = {
        bufnr = state.bufnr,
        ns = ns,
        hidden_ranges = vim.deepcopy(ranges or {}),
        priority = opts.priority or 200,
        checked = {},
        primed = true,
    }

    materialize_all(windows[state.winid])

    if type(vim.api.nvim__redraw) == 'function' then
        vim.api.nvim__redraw({ buf = state.bufnr, valid = false, flush = false })
    else
        vim.cmd.redraw()
    end

    return true, nil
end

---@param state marginalia.WindowState|table
---@param bufnr? integer
function M.clear_window_marks(state, bufnr)
    local ns = namespace_for_state(state)
    clear_namespace(bufnr or state.bufnr, ns)

    local entry = windows[state.winid]

    if entry then
        entry.checked = {}
    end
end

---@param state marginalia.WindowState
function M.clear_window(state)
    local entry = windows[state.winid]
    local ns = entry and entry.ns or namespace_for_state(state)

    clear_namespace(state.bufnr, ns)

    if state.identity and state.identity.bufnr and state.identity.bufnr ~= state.bufnr then
        clear_namespace(state.identity.bufnr, ns)
    end

    windows[state.winid] = nil
end

---@param winid integer
function M.remove_window(winid)
    local entry = windows[winid]

    if entry then
        clear_namespace(entry.bufnr, entry.ns)
    end

    windows[winid] = nil
end

---@param bufnr integer
function M.clear_buffer(bufnr)
    for _, entry in pairs(windows) do
        if entry.bufnr == bufnr then
            clear_namespace(bufnr, entry.ns)
            entry.checked = {}
        end
    end

    clear_namespace(bufnr, fallback_ns)
end

---@param state_or_winid? marginalia.WindowState|integer
---@return integer
function M.namespace(state_or_winid)
    if type(state_or_winid) == 'table' then
        return namespace_for_state(state_or_winid)
    end

    if type(state_or_winid) == 'number' then
        local entry = windows[state_or_winid]

        if entry then
            return entry.ns
        end
    end

    return fallback_ns
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
        ns = entry.ns,
        hidden_ranges = vim.deepcopy(entry.hidden_ranges),
        priority = entry.priority,
        checked = vim.deepcopy(entry.checked),
        primed = entry.primed,
    }
end

return M
