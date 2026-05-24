local window = require('marginalia.window')
local window_state = require('marginalia.window.state')

local M = {}

---@class marginalia.RefreshInvalidation
---@field winid integer
---@field opts table
---@field events table<string, true>

---@type table<integer, marginalia.RefreshInvalidation>
local pending = {}

---@type table<integer, boolean>
local scheduled = {}

local refresh_impl = window.refresh

---@param events table<string, true>
---@return string?
local function primary_event(events)
    if events.CursorMovedI then
        return 'CursorMovedI'
    end

    if events.CursorMoved then
        return 'CursorMoved'
    end

    if events.WinScrolled then
        return 'WinScrolled'
    end

    for event in pairs(events) do
        return event
    end

    return nil
end

---@param winid integer
local function drain(winid)
    scheduled[winid] = nil

    local invalidation = pending[winid]
    pending[winid] = nil

    if not invalidation or not window_state.valid_win(winid) or not window_state.is_attached(winid) then
        return
    end

    local opts = vim.tbl_extend('force', {}, invalidation.opts)
    opts._event = primary_event(invalidation.events)
    opts._events = invalidation.events

    refresh_impl(winid, opts)
end

---@param winid? integer
---@param opts? table
function M.enqueue(winid, opts)
    winid = window_state.normalize_winid(winid)

    if not window_state.valid_win(winid) then
        window_state.drop_invalid(winid)
        pending[winid] = nil
        scheduled[winid] = nil
        return
    end

    opts = opts or {}

    local invalidation = pending[winid]

    if not invalidation then
        invalidation = {
            winid = winid,
            opts = vim.tbl_extend('force', {}, opts),
            events = {},
        }
        pending[winid] = invalidation
    else
        invalidation.opts = vim.tbl_extend('force', invalidation.opts, opts)
    end

    local event = opts._event

    if type(event) == 'string' then
        invalidation.events[event] = true
    end

    if scheduled[winid] then
        return
    end

    scheduled[winid] = true

    vim.schedule(function()
        drain(winid)
    end)
end

---@param winid? integer
function M.cancel(winid)
    winid = window_state.normalize_winid(winid)
    pending[winid] = nil
    scheduled[winid] = nil
end

---@param fn fun(winid: integer, opts?: table)
function M._set_refresh_for_tests(fn)
    refresh_impl = fn
end

function M._reset_for_tests()
    pending = {}
    scheduled = {}
    refresh_impl = window.refresh
end

return M
