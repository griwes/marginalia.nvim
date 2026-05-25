local config = require('marginalia.config')
local window = require('marginalia.window')
local window_events = require('marginalia.window.events')

local M = {}

---@type marginalia.Config
M.config = config.normalize()

local augroup = vim.api.nvim_create_augroup('marginalia', { clear = true })
local mouse_keymaps = {}

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

---@param bufnr integer
local function install_mouse_keymaps(bufnr)
    if not M.config.input.mouse_scroll then
        if mouse_keymaps[bufnr] then
            pcall(vim.keymap.del, 'n', '<ScrollWheelUp>', { buffer = bufnr })
            pcall(vim.keymap.del, 'n', '<ScrollWheelDown>', { buffer = bufnr })
            mouse_keymaps[bufnr] = nil
        end

        return
    end

    vim.keymap.set('n', '<ScrollWheelUp>', function()
        M.scroll_mouse('up')
    end, {
        buffer = bufnr,
        silent = true,
        desc = 'Scroll Marginalia viewport up',
    })
    vim.keymap.set('n', '<ScrollWheelDown>', function()
        M.scroll_mouse('down')
    end, {
        buffer = bufnr,
        silent = true,
        desc = 'Scroll Marginalia viewport down',
    })
    mouse_keymaps[bufnr] = true
end

---@param winid integer
---@return boolean
local function attach_window(winid)
    local attached = window.attach(winid, refresh_opts(winid))

    if attached then
        install_mouse_keymaps(vim.api.nvim_win_get_buf(winid))
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

    if M.config.auto_attach and not window.is_attached(winid) then
        attach_window(winid)
        return
    end

    if window.is_attached(winid) then
        install_mouse_keymaps(vim.api.nvim_win_get_buf(winid))
        window_events.enqueue(winid, refresh_opts(winid, args and args.event or nil))
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
                attach_window(winid)
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

    if M.config.enabled and M.config.auto_attach then
        for _, winid in ipairs(vim.api.nvim_list_wins()) do
            attach_window(winid)
        end
    end

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
    winid = winid or vim.api.nvim_get_current_win()
    local attached = attach_window(winid)

    if attached then
        install_mouse_keymaps(vim.api.nvim_win_get_buf(winid))
    end

    return attached
end

---Disable Marginalia in a window.
---@param winid? integer
function M.disable(winid)
    window.detach(winid)
end

---Toggle Marginalia in a window.
---@param winid? integer
---@return boolean
function M.toggle(winid)
    return window.toggle(winid, M.config)
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
