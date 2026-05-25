local M = {}

---@class marginalia.RefreshEventClassification
---@field kind 'user_intent'|'external_invalidation'|'async_parse_completion'|'stale_async_parse_completion'|'transaction_echo'
---@field primary_event? string
---@field planner_event? string

---@param opts { event?: string, events?: table<string, true> }
---@return table<string, true>
local function event_set(opts)
    if opts.events then
        return opts.events
    end

    if opts.event then
        return { [opts.event] = true }
    end

    return {}
end

---@param event string?
---@return boolean
local function is_cursor_event(event)
    return event == 'CursorMoved' or event == 'CursorMovedI'
end

---@param event string?
---@return boolean
local function is_text_event(event)
    return event == 'TextChanged' or event == 'TextChangedI' or event == 'BufEnter' or event == 'BufWinEnter'
end

---@param event string?
---@return string?
local function option_name(event)
    if type(event) ~= 'string' then
        return nil
    end

    return event:match('^OptionSet:(.+)$')
end

---@param events table<string, true>
---@return string?
local function first_cursor_event(events)
    if events.CursorMovedI then
        return 'CursorMovedI'
    end

    if events.CursorMoved then
        return 'CursorMoved'
    end

    return nil
end

---@param events table<string, true>
---@return string?
local function first_text_event(events)
    for event in pairs(events) do
        if is_text_event(event) then
            return event
        end
    end

    return nil
end

---@param events table<string, true>
---@return string?
local function first_external_event(events)
    for event in pairs(events) do
        if event ~= 'WinScrolled' then
            return event
        end
    end

    return nil
end

---@param events table<string, true>
---@return string[], string?
local function option_events(events)
    local options = {}
    local primary

    for event in pairs(events) do
        local name = option_name(event)

        if name then
            options[#options + 1] = name
            primary = primary or event
        end
    end

    table.sort(options)
    return options, primary
end

---@param opts { events: table<string, true>, expected_scroll_echo?: { epoch: integer, cursor_row: integer, raw_topline: integer }, transaction_epoch?: integer, cursor_row: integer, raw_topline: integer }
---@return boolean
local function is_matching_scroll_echo(opts)
    local expected = opts.expected_scroll_echo

    if
        opts.events.WinScrolled ~= true
        or expected == nil
        or expected.epoch ~= opts.transaction_epoch
        or expected.cursor_row ~= opts.cursor_row
    then
        return false
    end

    if expected.raw_topline == opts.raw_topline then
        return true
    end

    return expected.raw_toplines and expected.raw_toplines[opts.raw_topline] == true
end

---@param opts { options: string[], expected_option_echo?: { epoch: integer, options: table<string, true> }, transaction_epoch?: integer }
---@return boolean
local function is_matching_option_echo(opts)
    local expected = opts.expected_option_echo

    if not expected or expected.epoch ~= opts.transaction_epoch or #opts.options == 0 then
        return false
    end

    for _, option in ipairs(opts.options) do
        if not expected.options[option] then
            return false
        end
    end

    return true
end

---@param opts { event?: string, events?: table<string, true>, expected_scroll_echo?: { epoch: integer, cursor_row: integer, raw_topline: integer }, expected_option_echo?: { epoch: integer, options: table<string, true> }, transaction_epoch?: integer, cursor_row: integer, raw_topline: integer, context_stale?: boolean }
---@return marginalia.RefreshEventClassification
function M.classify(opts)
    local events = event_set(opts)

    if events.ContextParsed then
        return {
            kind = opts.context_stale and 'stale_async_parse_completion' or 'async_parse_completion',
            primary_event = 'ContextParsed',
            planner_event = 'semantic_context_changed',
        }
    end

    local text_event = first_text_event(events)

    if text_event then
        return {
            kind = 'external_invalidation',
            primary_event = text_event,
            planner_event = 'semantic_context_changed',
        }
    end

    local cursor_event = first_cursor_event(events)

    if cursor_event then
        return {
            kind = 'user_intent',
            primary_event = cursor_event,
            planner_event = cursor_event,
        }
    end

    if events.MouseScrolled then
        return {
            kind = 'user_intent',
            primary_event = 'MouseScrolled',
            planner_event = 'MouseScrolled',
        }
    end

    local options, primary_option_event = option_events(events)

    if
        is_matching_option_echo({
            options = options,
            expected_option_echo = opts.expected_option_echo,
            transaction_epoch = opts.transaction_epoch,
        })
    then
        local scroll_is_absent_or_echo = not events.WinScrolled
            or is_matching_scroll_echo({
                events = events,
                expected_scroll_echo = opts.expected_scroll_echo,
                transaction_epoch = opts.transaction_epoch,
                cursor_row = opts.cursor_row,
                raw_topline = opts.raw_topline,
            })

        if scroll_is_absent_or_echo then
            return {
                kind = 'transaction_echo',
                primary_event = primary_option_event,
                planner_event = nil,
            }
        end
    elseif primary_option_event then
        return {
            kind = 'external_invalidation',
            primary_event = primary_option_event,
            planner_event = primary_option_event,
        }
    end

    if
        is_matching_scroll_echo({
            events = events,
            expected_scroll_echo = opts.expected_scroll_echo,
            transaction_epoch = opts.transaction_epoch,
            cursor_row = opts.cursor_row,
            raw_topline = opts.raw_topline,
        })
    then
        return {
            kind = 'transaction_echo',
            primary_event = 'WinScrolled',
            planner_event = nil,
        }
    end

    if events.WinScrolled then
        return {
            kind = 'user_intent',
            primary_event = 'WinScrolled',
            planner_event = 'WinScrolled',
        }
    end

    local event = first_external_event(events) or opts.event

    return {
        kind = 'external_invalidation',
        primary_event = event,
        planner_event = event,
    }
end

---@param state marginalia.WindowState|table
---@param opts { refresh_event?: string, refresh_events?: table<string, true>, cursor_row: integer, raw_topline: integer }
---@return marginalia.RefreshEventClassification
function M.classify_refresh(state, opts)
    local events = event_set({
        event = opts.refresh_event,
        events = opts.refresh_events,
    })
    local classification = M.classify({
        event = opts.refresh_event,
        events = events,
        expected_scroll_echo = state.transaction and state.transaction.expected_scroll_echo,
        expected_option_echo = state.transaction and state.transaction.expected_option_echo,
        transaction_epoch = state.transaction and state.transaction.epoch,
        cursor_row = opts.cursor_row,
        raw_topline = opts.raw_topline,
    })

    if not state.transaction then
        return classification
    end

    if classification.kind == 'transaction_echo' then
        local options = option_events(events)

        if
            is_matching_scroll_echo({
                events = events,
                expected_scroll_echo = state.transaction.expected_scroll_echo,
                transaction_epoch = state.transaction.epoch,
                cursor_row = opts.cursor_row,
                raw_topline = opts.raw_topline,
            })
        then
            state.transaction.expected_scroll_echo = nil
        end

        if
            is_matching_option_echo({
                options = options,
                expected_option_echo = state.transaction.expected_option_echo,
                transaction_epoch = state.transaction.epoch,
            })
        then
            state.transaction.expected_option_echo = nil
        end
    elseif events.WinScrolled or events.CursorMoved or events.CursorMovedI then
        state.transaction.expected_scroll_echo = nil
        state.transaction.expected_option_echo = nil
    end

    return classification
end

return M
