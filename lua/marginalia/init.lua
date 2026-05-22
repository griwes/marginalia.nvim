local config = require('marginalia.config')
local context = require('marginalia.context')
local policy = require('marginalia.policy')
local window = require('marginalia.window')

local M = {}

---@type marginalia.Config
M.config = config.normalize()

local augroup = vim.api.nvim_create_augroup('marginalia', { clear = true })

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
end

local function refresh_current()
    if not M.config.enabled then
        return
    end

    if M.config.auto_attach and not window.is_attached() then
        window.attach(0, M.config)
        return
    end

    if window.is_attached() then
        window.refresh(0, M.config)
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
                window.attach(0, M.config)
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

    vim.api.nvim_create_autocmd('WinClosed', {
        group = augroup,
        callback = function(args)
            window.detach(tonumber(args.match))
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
            window.attach(winid, M.config)
        end
    end

    return M.config
end

---Return context frames for the current or provided window.
---@param opts? table
---@return marginalia.ContextResult
function M.get_context(opts)
    return context.for_window(vim.tbl_deep_extend('force', M.config, opts or {}))
end

---Collect context frames from a provided tree node.
---@param node any
---@param opts? marginalia.Config
---@return marginalia.ContextFrame[]
function M.collect_ancestors(node, opts)
    return context.collect_ancestors(node, vim.tbl_deep_extend('force', M.config, opts or {}))
end

---Compute protected and hidden rows without mutating the editor.
---@param opts table
---@return { protected_rows: integer[], hidden_ranges: marginalia.HiddenRange[] }
function M.plan_hidden_ranges(opts)
    return policy.plan(opts)
end

---Enable Marginalia in a window.
---@param winid? integer
---@return boolean
function M.enable(winid)
    return window.attach(winid, M.config)
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
---@return { protected_rows: integer[], hidden_ranges: marginalia.HiddenRange[] }?
function M.refresh(winid)
    return window.refresh(winid, M.config)
end

---Return Marginalia window state for tests and integrations.
---@param winid? integer
---@return marginalia.WindowState?
function M.window_state(winid)
    return window.state(winid)
end

return M
