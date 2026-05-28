local config = require('marginalia.config')
local window = require('marginalia.window')
local window_events = require('marginalia.window.events')

local M = {}

---@type marginalia.Config
M.config = config.normalize()

local augroup = vim.api.nvim_create_augroup('marginalia', { clear = true })

---@class marginalia.MouseKeymap
---@field callback fun(): string

---@type table<integer, table<string, marginalia.MouseKeymap>>
local mouse_keymaps = {}

local mouse_scroll_mappings = {
    ['<ScrollWheelUp>'] = 'up',
    ['<ScrollWheelDown>'] = 'down',
}

---@param winid integer
---@param event? string
---@return marginalia.Config|table
local function refresh_opts(winid, event)
    return vim.tbl_extend('force', M.config, {
        _event = event,
        _on_context_publish = function()
            window_events.enqueue(winid, refresh_opts(winid, 'ContextParsed'))
        end,
    })
end

---@return integer
local function mouse_scroll_rows()
    local rows = tonumber(vim.go.mousescroll:match('ver:(%d+)'))

    if not rows then
        return 3
    end

    return math.max(0, math.floor(rows))
end

---@param winid integer
---@return integer?
local function native_scroll_delta(winid)
    local event = vim.v.event

    if type(event) ~= 'table' then
        return nil
    end

    local win_event = event[winid] or event[tostring(winid)]

    if type(win_event) ~= 'table' or type(win_event.topline) ~= 'number' or win_event.topline == 0 then
        return nil
    end

    return win_event.topline
end

---@param bufnr integer
---@param lhs string
---@return table?
local function buffer_keymap(bufnr, lhs)
    if not vim.api.nvim_buf_is_valid(bufnr) then
        return nil
    end

    for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(bufnr, 'n')) do
        if mapping.lhs == lhs then
            return mapping
        end
    end

    return nil
end

---@param bufnr integer
---@param lhs string
local function remove_owned_mouse_keymap(bufnr, lhs)
    local owned = mouse_keymaps[bufnr] and mouse_keymaps[bufnr][lhs]

    if not owned then
        return
    end

    local current = buffer_keymap(bufnr, lhs)

    if current and current.callback == owned.callback then
        pcall(vim.keymap.del, 'n', lhs, { buffer = bufnr })
    end

    mouse_keymaps[bufnr][lhs] = nil

    if next(mouse_keymaps[bufnr]) == nil then
        mouse_keymaps[bufnr] = nil
    end
end

---@param bufnr integer
---@param lhs string
---@param direction 'up'|'down'
local function install_mouse_keymap(bufnr, lhs, direction)
    local owned = mouse_keymaps[bufnr] and mouse_keymaps[bufnr][lhs]
    local current = buffer_keymap(bufnr, lhs)

    if current and (not owned or current.callback ~= owned.callback) then
        if owned then
            mouse_keymaps[bufnr][lhs] = nil

            if next(mouse_keymaps[bufnr]) == nil then
                mouse_keymaps[bufnr] = nil
            end
        end

        return
    end

    if owned and current then
        return
    end

    local callback = function()
        if M.scroll_mouse(direction) then
            return '<Ignore>'
        end

        return lhs
    end

    vim.keymap.set('n', lhs, callback, {
        buffer = bufnr,
        desc = 'Scroll Marginalia viewport ' .. direction,
        expr = true,
        replace_keycodes = true,
        silent = true,
    })

    mouse_keymaps[bufnr] = mouse_keymaps[bufnr] or {}
    mouse_keymaps[bufnr][lhs] = { callback = callback }
end

local function sync_mouse_keymaps()
    local desired = {}

    if M.config.input.mouse_scroll then
        for _, winid in ipairs(vim.api.nvim_list_wins()) do
            if window.is_attached(winid) then
                desired[vim.api.nvim_win_get_buf(winid)] = true
            end
        end
    end

    local tracked_buffers = vim.tbl_keys(mouse_keymaps)

    for _, bufnr in ipairs(tracked_buffers) do
        if not desired[bufnr] then
            for lhs in pairs(mouse_scroll_mappings) do
                remove_owned_mouse_keymap(bufnr, lhs)
            end
        end
    end

    for bufnr in pairs(desired) do
        for lhs, direction in pairs(mouse_scroll_mappings) do
            install_mouse_keymap(bufnr, lhs, direction)
        end
    end
end

---@param winid integer
---@return boolean
local function suitable_for_auto_attach(winid)
    if not vim.api.nvim_win_is_valid(winid) then
        return false
    end

    local bufnr = vim.api.nvim_win_get_buf(winid)

    if
        not vim.api.nvim_buf_is_valid(bufnr)
        or not vim.api.nvim_buf_is_loaded(bufnr)
        or not vim.bo[bufnr].buflisted
        or vim.bo[bufnr].buftype ~= ''
    then
        return false
    end

    return not vim.api.nvim_buf_get_name(bufnr):match('^[%a][%w+.-]*://')
end

---@param winid integer
---@param automatic? boolean
---@return boolean
local function attach_window(winid, automatic)
    if automatic and not suitable_for_auto_attach(winid) then
        return false
    end

    local attached = window.attach(winid, refresh_opts(winid))

    if attached then
        sync_mouse_keymaps()
    end

    return attached
end

local function install_commands()
    vim.api.nvim_create_user_command('MarginaliaEnable', function()
        M.enable()
    end, {
        desc = 'Enable Marginalia in the current window',
    })

    vim.api.nvim_create_user_command('MarginaliaDisable', function()
        M.disable()
    end, {
        desc = 'Disable Marginalia in the current window',
    })

    vim.api.nvim_create_user_command('MarginaliaToggle', function()
        M.toggle()
    end, {
        desc = 'Toggle Marginalia in the current window',
    })

    vim.api.nvim_create_user_command('MarginaliaRefresh', function()
        M.refresh()
    end, {
        desc = 'Refresh Marginalia in the current window',
    })

    vim.api.nvim_create_user_command('MarginaliaDebug', function()
        vim.print(M.debug_snapshot())
    end, {
        desc = 'Print Marginalia debug snapshot for the current window',
    })
end

local function refresh_current(args)
    if not M.config.enabled then
        return
    end

    local winid = vim.api.nvim_get_current_win()

    if not suitable_for_auto_attach(winid) then
        if window.is_attached(winid) then
            window_events.cancel(winid)
            window.detach(winid)
            sync_mouse_keymaps()
        end

        return
    end

    if M.config.auto_attach and not window.is_attached(winid) then
        attach_window(winid, true)
        return
    end

    if window.is_attached(winid) then
        sync_mouse_keymaps()
        local event = args and args.event or nil
        local opts = refresh_opts(winid, event)

        if event == 'WinScrolled' then
            opts._native_scroll_delta = native_scroll_delta(winid)
        end

        window_events.enqueue(winid, opts)
    end
end

local function install_autocmds()
    vim.api.nvim_clear_autocmds({ group = augroup })

    if not M.config.enabled then
        return
    end

    vim.api.nvim_create_autocmd({ 'BufWinEnter', 'WinEnter' }, {
        group = augroup,
        callback = function()
            if M.config.auto_attach then
                local winid = vim.api.nvim_get_current_win()
                attach_window(winid, true)
            end
        end,
    })

    vim.api.nvim_create_autocmd(
        { 'BufEnter', 'CursorMoved', 'CursorMovedI', 'WinScrolled', 'TextChanged', 'TextChangedI' },
        {
            group = augroup,
            callback = refresh_current,
        }
    )

    vim.api.nvim_create_autocmd('OptionSet', {
        group = augroup,
        pattern = { 'conceallevel', 'scrolloff' },
        callback = function(args)
            refresh_current({ event = 'OptionSet:' .. args.match })
        end,
    })

    vim.api.nvim_create_autocmd('WinClosed', {
        group = augroup,
        callback = function(args)
            local winid = tonumber(args.match)
            window_events.cancel(winid)
            window.detach(winid)
            sync_mouse_keymaps()
        end,
    })
end

---Configure the plugin.
---@param opts? marginalia.Config
---@return marginalia.Config
function M.setup(opts)
    M.config = config.normalize(opts)
    install_commands()
    install_autocmds()

    if not M.config.enabled then
        for _, winid in ipairs(vim.api.nvim_list_wins()) do
            if window.is_attached(winid) then
                window_events.cancel(winid)
                window.detach(winid)
            end
        end
    elseif M.config.auto_attach then
        for _, winid in ipairs(vim.api.nvim_list_wins()) do
            attach_window(winid, true)
        end
    end

    sync_mouse_keymaps()

    return M.config
end

---@param direction 'up'|'down'
---@param winid? integer
---@return boolean
function M.scroll_mouse(direction, winid)
    local mouse = vim.fn.getmousepos()

    if not winid and type(mouse) == 'table' and type(mouse.winid) == 'number' and mouse.winid > 0 then
        winid = mouse.winid
    end

    winid = winid or vim.api.nvim_get_current_win()

    if not window.is_attached(winid) then
        return false
    end

    local rows = mouse_scroll_rows() * math.max(1, vim.v.count1 or 1)

    if rows == 0 then
        return true
    end

    local delta = direction == 'up' and -rows or rows
    local opts = refresh_opts(winid, 'MouseScrolled')
    opts._logical_scroll_delta = delta
    window_events.enqueue(winid, opts)
    return true
end

---Enable Marginalia in a window.
---@param winid? integer
---@return boolean
function M.enable(winid)
    if not winid or winid == 0 then
        winid = vim.api.nvim_get_current_win()
    end

    local attached = attach_window(winid)

    return attached
end

---Disable Marginalia in a window.
---@param winid? integer
function M.disable(winid)
    if not winid or winid == 0 then
        winid = vim.api.nvim_get_current_win()
    end

    window_events.cancel(winid)
    window.detach(winid)
    sync_mouse_keymaps()
end

---Toggle Marginalia in a window.
---@param winid? integer
---@return boolean
function M.toggle(winid)
    if not winid or winid == 0 then
        winid = vim.api.nvim_get_current_win()
    end

    if window.is_attached(winid) then
        M.disable(winid)
        return false
    end

    return M.enable(winid)
end

---Refresh Marginalia in a window.
---@param winid? integer
---@return { visible_rows: integer[], hidden_ranges: marginalia.HiddenRange[] }?
function M.refresh(winid)
    return window.refresh(winid, M.config)
end

---Return Marginalia window state for tests and integrations.
---@param winid? integer
---@return marginalia.WindowState?
function M.window_state(winid)
    return window.state(winid)
end

---Return a structured debug snapshot for the current or selected window.
---@param winid? integer
---@return table?
function M.debug_snapshot(winid)
    return window.debug_snapshot(winid)
end

return M
