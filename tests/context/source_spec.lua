local source = require('marginalia.context.source')

---@return integer
local function scratch_buffer()
    local bufnr = vim.api.nvim_create_buf(false, true)

    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        'local M = {}',
        'return M',
    })
    vim.api.nvim_win_set_buf(0, bufnr)
    vim.api.nvim_win_set_cursor(0, { 1, 0 })

    return bufnr
end

---@param opts? { immediate?: table, async?: boolean, lang?: string }
---@return table, table
local function fake_parser(opts)
    opts = opts or {}

    local state = {
        callbacks = {},
        calls = 0,
    }
    local parser = {}

    function parser:lang()
        return opts.lang or 'lua'
    end

    function parser:parse(_, callback)
        state.calls = state.calls + 1

        if opts.async then
            state.callbacks[#state.callbacks + 1] = callback
            return nil
        end

        return opts.immediate
    end

    return parser, state
end

describe('marginalia.context.source', function()
    local original_get_parser
    local original_query_get
    local original_query_get_query

    before_each(function()
        source._reset_for_tests()
        original_get_parser = vim.treesitter.get_parser
        original_query_get = vim.treesitter.query.get
        original_query_get_query = vim.treesitter.query.get_query
    end)

    after_each(function()
        source._reset_for_tests()
        vim.treesitter.get_parser = original_get_parser
        vim.treesitter.query.get = original_query_get
        vim.treesitter.query.get_query = original_query_get_query
    end)

    it('returns parse_pending while an async parse is outstanding and publishes the result later', function()
        local bufnr = scratch_buffer()
        local tree = { root = function() end }
        local parser, parser_state = fake_parser({ async = true })
        local query = { captures = {} }
        local published = false

        vim.treesitter.get_parser = function()
            return parser
        end
        vim.treesitter.query.get = function()
            return query
        end

        local snapshot, reason = source.snapshot({
            bufnr = bufnr,
            winid = 0,
            on_publish = function(published_bufnr)
                published = published_bufnr == bufnr
            end,
        })

        assert.is_nil(snapshot)
        assert.are.equal('parse_pending', reason)
        assert.are.equal(1, parser_state.calls)
        assert.are.equal(1, #parser_state.callbacks)

        parser_state.callbacks[1](nil, { tree })

        vim.wait(100, function()
            return published
        end)

        local cached_snapshot = assert(source.snapshot({ bufnr = bufnr, winid = 0 }))

        assert.is_false(cached_snapshot.stale == true)
        assert.are.same({ tree }, cached_snapshot.trees)
        assert.are.same(query, cached_snapshot.context_query)

        vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('publishes one shared-buffer async parse to every waiting window', function()
        local bufnr = scratch_buffer()
        local first_win = vim.api.nvim_get_current_win()
        local tree = { root = function() end }
        local parser, parser_state = fake_parser({ async = true })
        local published = {}

        vim.cmd('belowright split')
        local second_win = vim.api.nvim_get_current_win()

        vim.api.nvim_win_set_buf(first_win, bufnr)
        vim.api.nvim_win_set_buf(second_win, bufnr)
        vim.treesitter.get_parser = function()
            return parser
        end
        vim.treesitter.query.get = function()
            return { captures = {} }
        end

        source.snapshot({
            bufnr = bufnr,
            winid = first_win,
            on_publish = function()
                published[first_win] = (published[first_win] or 0) + 1
            end,
        })
        source.snapshot({
            bufnr = bufnr,
            winid = second_win,
            on_publish = function()
                published[second_win] = (published[second_win] or 0) + 1
            end,
        })

        assert.are.equal(1, parser_state.calls)
        assert.are.equal(1, #parser_state.callbacks)

        parser_state.callbacks[1](nil, { tree })

        vim.wait(100, function()
            return published[first_win] == 1 and published[second_win] == 1
        end)

        assert.are.equal(1, published[first_win])
        assert.are.equal(1, published[second_win])

        vim.api.nvim_win_close(second_win, true)
        vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('selects the injected language tree and its context query at the cursor', function()
        local bufnr = scratch_buffer()
        local root_tree = { root = function() end }
        local injected_tree = { root = function() end }
        local root_parser = assert(fake_parser({ immediate = { root_tree }, lang = 'markdown' }))
        local injected_parser = {}
        local requested_range
        local requested_lang
        local injected_query = { captures = {} }

        function injected_parser:lang()
            return 'lua'
        end

        function injected_parser:trees()
            return { injected_tree }
        end

        function root_parser:language_for_range(range)
            requested_range = range
            return injected_parser
        end

        vim.treesitter.get_parser = function()
            return root_parser
        end
        vim.treesitter.query.get = function(lang)
            requested_lang = lang
            return injected_query
        end

        local snapshot = assert(source.snapshot({ bufnr = bufnr, winid = 0 }))

        assert.are.same({ 0, 0, 0, 0 }, requested_range)
        assert.are.equal('lua', requested_lang)
        assert.are.same(injected_parser, snapshot.parser)
        assert.are.same({ injected_tree }, snapshot.trees)
        assert.are.same(injected_query, snapshot.context_query)

        vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('keys cached trees by the resolved parser language and parser identity', function()
        local bufnr = scratch_buffer()
        local lua_tree = { root = function() end }
        local python_tree = { root = function() end }
        local lua_parser, lua_state = fake_parser({ immediate = { lua_tree }, lang = 'lua' })
        local python_parser, python_state = fake_parser({ immediate = { python_tree }, lang = 'python' })
        local selected_parser = lua_parser

        vim.treesitter.get_parser = function()
            return selected_parser
        end
        vim.treesitter.query.get = function(lang)
            return { captures = {}, lang = lang }
        end

        local lua_snapshot = assert(source.snapshot({ bufnr = bufnr, winid = 0 }))

        selected_parser = python_parser

        local python_snapshot = assert(source.snapshot({ bufnr = bufnr, winid = 0 }))

        assert.are.same({ lua_tree }, lua_snapshot.trees)
        assert.are.equal('lua', lua_snapshot.context_query.lang)
        assert.are.same({ python_tree }, python_snapshot.trees)
        assert.are.equal('python', python_snapshot.context_query.lang)
        assert.are.equal(1, lua_state.calls)
        assert.are.equal(1, python_state.calls)

        vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('reports no_parser when Tree-sitter parser acquisition fails', function()
        local bufnr = scratch_buffer()

        vim.treesitter.get_parser = function()
            error('missing parser')
        end

        local result = source.for_window({
            bufnr = bufnr,
            winid = 0,
            lang = 'marginalia_missing_language',
        })

        assert.are.same({}, result.frames)
        assert.are.equal('no_parser', result.reason)

        vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('uses the previous stable tree while a newer parse is pending', function()
        local bufnr = scratch_buffer()
        local tree = { root = function() end }
        local parser, parser_state = fake_parser({ immediate = { tree } })

        vim.treesitter.get_parser = function()
            return parser
        end
        vim.treesitter.query.get = function()
            return { captures = {} }
        end

        local initial_snapshot = assert(source.snapshot({ bufnr = bufnr, winid = 0 }))
        assert.is_false(initial_snapshot.stale == true)

        parser.parse = function(_, _, callback)
            parser_state.calls = parser_state.calls + 1
            parser_state.callbacks[#parser_state.callbacks + 1] = callback
            return nil
        end

        vim.api.nvim_buf_set_lines(bufnr, 0, 1, false, { 'local changed = true' })

        local stale_snapshot = assert(source.snapshot({ bufnr = bufnr, winid = 0 }))

        assert.is_true(stale_snapshot.stale)
        assert.are.same({ tree }, stale_snapshot.trees)

        vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('rejects stale async parse callbacks by generation', function()
        local bufnr = scratch_buffer()
        local first_tree = { root = function() end }
        local second_tree = { root = function() end }
        local parser, parser_state = fake_parser({ async = true })

        vim.treesitter.get_parser = function()
            return parser
        end
        vim.treesitter.query.get = function()
            return { captures = {} }
        end

        source.snapshot({ bufnr = bufnr, winid = 0 })
        vim.api.nvim_buf_set_lines(bufnr, 0, 1, false, { 'local changed = true' })
        source.snapshot({ bufnr = bufnr, winid = 0 })

        assert.are.equal(2, #parser_state.callbacks)

        parser_state.callbacks[1](nil, { first_tree })
        parser_state.callbacks[2](nil, { second_tree })

        vim.wait(100, function()
            local snapshot = source.snapshot({ bufnr = bufnr, winid = 0 })
            return snapshot and snapshot.trees and snapshot.trees[1] == second_tree
        end)

        local snapshot = assert(source.snapshot({ bufnr = bufnr, winid = 0 }))

        assert.are.same({ second_tree }, snapshot.trees)

        vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
end)
