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
