local M = {}

local provider = require('marginalia.render.provider')

local namespace_prefix = 'marginalia'

---@param winid integer
---@return boolean
local function valid_win(winid)
    return type(winid) == 'number' and vim.api.nvim_win_is_valid(winid)
end

---@param state marginalia.WindowState
---@param option string
local function mark_option_echo(state, option)
    state.transaction.pending_option_echoes = state.transaction.pending_option_echoes or {}
    state.transaction.pending_option_echoes[option] = true
end

---@param suffix? string
---@return integer
function M.namespace(suffix)
    if suffix and suffix ~= '' then
        return vim.api.nvim_create_namespace(namespace_prefix .. '.' .. suffix)
    end

    return vim.api.nvim_create_namespace(namespace_prefix)
end

---@param view table
function M.restore_view(view)
    vim.fn.winrestview(view)
end

---@param winid integer
---@param topline integer
function M.restore_target_topline(winid, topline)
    vim.api.nvim_win_call(winid, function()
        local scrolloff = vim.wo.scrolloff

        vim.wo.scrolloff = 0
        vim.fn.winrestview({ topline = topline })
        vim.wo.scrolloff = scrolloff
        vim.fn.line('w0')
    end)
end

---@param state marginalia.WindowState
---@param conceallevel integer
function M.apply_conceallevel(state, conceallevel)
    local options = state.options

    if not valid_win(state.winid) or options.conceallevel_applied then
        return
    end

    if vim.wo[state.winid].conceallevel < conceallevel then
        vim.wo[state.winid].conceallevel = conceallevel
        options.conceallevel_applied = true
        mark_option_echo(state, 'conceallevel')
    end
end

---@param state marginalia.WindowState
function M.restore_conceallevel(state)
    local options = state.options

    if not valid_win(state.winid) or not options.conceallevel_applied then
        return
    end

    vim.wo[state.winid].conceallevel = options.original_conceallevel
    options.conceallevel_applied = false
    mark_option_echo(state, 'conceallevel')
end

---@param state marginalia.WindowState
function M.suppress_scrolloff(state)
    local options = state.options

    if not valid_win(state.winid) or options.scrolloff_suppressed then
        return
    end

    options.original_scrolloff = vim.wo[state.winid].scrolloff
    options.original_global_scrolloff = vim.go.scrolloff
    options.scrolloff_restore_global = options.original_scrolloff == options.original_global_scrolloff
    vim.api.nvim_win_call(state.winid, function()
        vim.cmd('setlocal scrolloff=0')
    end)
    options.scrolloff_suppressed = true
    mark_option_echo(state, 'scrolloff')
end

---@param state marginalia.WindowState
function M.restore_scrolloff(state)
    local options = state.options

    if not valid_win(state.winid) or not options.scrolloff_suppressed then
        return
    end

    if options.scrolloff_restore_global then
        vim.api.nvim_win_call(state.winid, function()
            vim.cmd('setlocal scrolloff<')
        end)
    else
        vim.wo[state.winid].scrolloff = options.original_scrolloff
    end

    options.scrolloff_suppressed = false
    mark_option_echo(state, 'scrolloff')
end

---@param state marginalia.WindowState
---@param plan { hidden_ranges?: marginalia.HiddenRange[] }
---@param conceallevel integer
function M.apply_window_options(state, plan, conceallevel)
    if #(plan.hidden_ranges or {}) > 0 then
        M.suppress_scrolloff(state)
        M.apply_conceallevel(state, conceallevel)
        return
    end

    M.restore_conceallevel(state)
    M.restore_scrolloff(state)
end

---@param bufnr integer
---@param ns integer
function M.clear(bufnr, ns)
    if not vim.api.nvim_buf_is_valid(bufnr) then
        return
    end

    vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
end

---@param state marginalia.WindowState
function M.clear_state(state)
    M.clear(state.bufnr, state.ns)
    provider.clear_window(state)
end

return M
