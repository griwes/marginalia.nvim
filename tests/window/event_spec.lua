local event = require('marginalia.window.event')

describe('marginalia.window.event', function()
    it('classifies matching WinScrolled events as transaction echoes', function()
        local classification = event.classify({
            event = 'WinScrolled',
            transaction_epoch = 3,
            cursor_row = 20,
            raw_topline = 11,
            expected_scroll_echo = {
                epoch = 3,
                cursor_row = 20,
                raw_topline = 11,
            },
        })

        assert.are.equal('transaction_echo', classification.kind)
        assert.is_nil(classification.planner_event)
    end)

    it('keeps non-matching WinScrolled events as user intent', function()
        local classification = event.classify({
            event = 'WinScrolled',
            transaction_epoch = 4,
            cursor_row = 20,
            raw_topline = 12,
            expected_scroll_echo = {
                epoch = 3,
                cursor_row = 20,
                raw_topline = 11,
            },
        })

        assert.are.equal('user_intent', classification.kind)
        assert.are.equal('WinScrolled', classification.planner_event)
    end)

    it('classifies async parse completion as semantic context change', function()
        local classification = event.classify({
            event = 'ContextParsed',
            cursor_row = 10,
            raw_topline = 1,
        })

        assert.are.equal('async_parse_completion', classification.kind)
        assert.are.equal('semantic_context_changed', classification.planner_event)
    end)

    it('classifies stale async parse completion separately', function()
        local classification = event.classify({
            event = 'ContextParsed',
            cursor_row = 10,
            raw_topline = 1,
            context_stale = true,
        })

        assert.are.equal('stale_async_parse_completion', classification.kind)
        assert.are.equal('semantic_context_changed', classification.planner_event)
    end)

    it('keeps coalesced async parse completion ahead of matching scroll echoes', function()
        local classification = event.classify({
            event = 'WinScrolled',
            events = {
                ContextParsed = true,
                WinScrolled = true,
            },
            transaction_epoch = 3,
            cursor_row = 20,
            raw_topline = 11,
            expected_scroll_echo = {
                epoch = 3,
                cursor_row = 20,
                raw_topline = 11,
            },
        })

        assert.are.equal('async_parse_completion', classification.kind)
        assert.are.equal('ContextParsed', classification.primary_event)
        assert.are.equal('semantic_context_changed', classification.planner_event)
    end)

    it('keeps coalesced cursor movement ahead of matching scroll echoes', function()
        local classification = event.classify({
            event = 'WinScrolled',
            events = {
                CursorMoved = true,
                WinScrolled = true,
            },
            transaction_epoch = 3,
            cursor_row = 20,
            raw_topline = 11,
            expected_scroll_echo = {
                epoch = 3,
                cursor_row = 20,
                raw_topline = 11,
            },
        })

        assert.are.equal('user_intent', classification.kind)
        assert.are.equal('CursorMoved', classification.primary_event)
        assert.are.equal('CursorMoved', classification.planner_event)
    end)

    it('classifies matching option mutations as transaction echoes', function()
        local classification = event.classify({
            event = 'OptionSet:scrolloff',
            transaction_epoch = 3,
            cursor_row = 20,
            raw_topline = 11,
            expected_option_echo = {
                epoch = 3,
                options = {
                    scrolloff = true,
                },
            },
        })

        assert.are.equal('transaction_echo', classification.kind)
        assert.are.equal('OptionSet:scrolloff', classification.primary_event)
        assert.is_nil(classification.planner_event)
    end)

    it('keeps unexpected option mutations as external invalidations', function()
        local classification = event.classify({
            event = 'OptionSet:scrolloff',
            transaction_epoch = 3,
            cursor_row = 20,
            raw_topline = 11,
            expected_option_echo = {
                epoch = 3,
                options = {
                    conceallevel = true,
                },
            },
        })

        assert.are.equal('external_invalidation', classification.kind)
        assert.are.equal('OptionSet:scrolloff', classification.primary_event)
        assert.are.equal('OptionSet:scrolloff', classification.planner_event)
    end)

    it('classifies text events as external invalidations', function()
        local classification = event.classify({
            event = 'TextChanged',
            cursor_row = 10,
            raw_topline = 1,
        })

        assert.are.equal('external_invalidation', classification.kind)
        assert.are.equal('semantic_context_changed', classification.planner_event)
    end)

    it('classifies refreshes and clears consumed transaction echo state', function()
        local state = {
            transaction = {
                epoch = 3,
                expected_scroll_echo = {
                    epoch = 3,
                    cursor_row = 20,
                    raw_topline = 11,
                },
                expected_option_echo = {
                    epoch = 3,
                    options = {
                        scrolloff = true,
                    },
                },
            },
        }

        local classification = event.classify_refresh(state, {
            refresh_event = 'WinScrolled',
            cursor_row = 20,
            raw_topline = 11,
        })

        assert.are.equal('transaction_echo', classification.kind)
        assert.is_nil(state.transaction.expected_scroll_echo)
        assert.is_nil(state.transaction.expected_option_echo)
    end)
end)
