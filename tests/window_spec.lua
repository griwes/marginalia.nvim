local window = require('marginalia.window')

describe('marginalia.window', function()
    local previous_conceallevel
    local previous_scrolloff

    local function line_buffer(count)
        local bufnr = vim.api.nvim_create_buf(false, true)
        local lines = {}

        for row = 1, count do
            lines[row] = 'line ' .. row
        end

        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
        return bufnr
    end

    before_each(function()
        previous_conceallevel = vim.wo.conceallevel
        previous_scrolloff = vim.wo.scrolloff
        vim.wo.conceallevel = 0
        vim.wo.scrolloff = 0
    end)

    after_each(function()
        window.detach()
        vim.wo.conceallevel = previous_conceallevel
        vim.wo.scrolloff = previous_scrolloff
    end)

    it('sets and restores conceallevel around a non-empty conceal plan', function()
        local bufnr = line_buffer(40)

        vim.api.nvim_win_set_buf(0, bufnr)
        vim.api.nvim_win_set_height(0, 8)
        vim.api.nvim_win_set_cursor(0, { 12, 0 })
        vim.fn.winrestview({ topline = 10 })

        assert.is_true(window.attach(0, {
            conceallevel = 2,
            frames = {
                { row = 1 },
            },
        }))
        assert.are.equal(2, vim.wo.conceallevel)

        window.detach()

        assert.are.equal(0, vim.wo.conceallevel)
        vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('leaves conceallevel alone when no context is available', function()
        assert.is_true(window.attach(0, { conceallevel = 2, context_result = { frames = {}, reason = 'no_parser' } }))
        assert.are.equal(0, vim.wo.conceallevel)
    end)

    it('applies a top-context stitching plan to the attached window', function()
        local bufnr = line_buffer(20)

        vim.api.nvim_win_set_buf(0, bufnr)
        vim.api.nvim_win_set_height(0, 8)
        vim.api.nvim_win_set_cursor(0, { 8, 0 })
        vim.fn.winrestview({ topline = 5 })

        window.attach(0, {
            max_depth = 4,
            skip_node_types = {},
            frames = {
                { row = 1 },
                { row = 3 },
            },
        })
        local state = window.state()
        local marks = vim.api.nvim_buf_get_extmarks(bufnr, state.ns, 0, -1, { details = true })

        assert.are.same({
            { start_row = 2, end_row = 2 },
            { start_row = 4, end_row = 6 },
        }, state.last_plan.hidden_ranges)
        assert.are.equal(2, #marks)
        assert.are.equal('', marks[1][4].conceal_lines)

        vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('protects scrolloff rows around the cursor', function()
        local bufnr = vim.api.nvim_create_buf(false, true)

        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
            'function demo()',
            '  one()',
            '  two()',
            '  three()',
            '  four()',
            '  five()',
            'end',
        })
        vim.api.nvim_win_set_buf(0, bufnr)
        vim.api.nvim_win_set_cursor(0, { 6, 2 })
        vim.wo.scrolloff = 2

        window.attach(0, {
            frames = {
                { row = 1 },
            },
        })
        local state = window.state()

        assert.are.same({ 1, 4, 5, 6, 7 }, state.last_plan.protected_rows)

        vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('does not conceal rows below the context-covered viewport top', function()
        local bufnr = line_buffer(140)

        vim.api.nvim_win_set_buf(0, bufnr)
        vim.api.nvim_win_set_height(0, 18)
        vim.api.nvim_win_set_cursor(0, { 89, 0 })
        vim.fn.winrestview({ topline = 80 })

        window.attach(0, {
            respect_scrolloff = false,
            frames = {
                { row = 71 },
                { row = 72 },
                { row = 76 },
                { row = 77 },
                { row = 81 },
                { row = 82 },
                { row = 86 },
                { row = 87 },
            },
        })

        local state = window.state()

        for _, range in ipairs(state.last_plan.hidden_ranges) do
            assert.is_true(range.end_row < 86)
        end

        vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('does not let scrolloff protect rows replaced by context', function()
        local bufnr = line_buffer(140)

        vim.api.nvim_win_set_buf(0, bufnr)
        vim.api.nvim_win_set_height(0, 18)
        vim.api.nvim_win_set_cursor(0, { 89, 0 })
        vim.wo.scrolloff = 5
        vim.fn.winrestview({ topline = 80 })

        window.attach(0, {
            frames = {
                { row = 71 },
                { row = 72 },
                { row = 76 },
                { row = 77 },
                { row = 81 },
                { row = 82 },
                { row = 86 },
                { row = 87 },
            },
        })

        assert.are.same({
            { start_row = 73, end_row = 75 },
            { start_row = 78, end_row = 80 },
            { start_row = 83, end_row = 85 },
        }, window.state().last_plan.hidden_ranges)

        vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('anchors the view at the first stitched context row', function()
        local bufnr = line_buffer(40)

        vim.api.nvim_win_set_buf(0, bufnr)
        vim.api.nvim_win_set_height(0, 8)
        vim.api.nvim_win_set_cursor(0, { 12, 0 })
        vim.fn.winrestview({ topline = 10 })

        window.attach(0, {
            respect_scrolloff = false,
            frames = {
                { row = 1 },
                { row = 2 },
            },
        })

        assert.are.equal(1, vim.fn.winsaveview().topline)

        vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('preserves the logical viewport when refreshing an anchored context', function()
        local bufnr = line_buffer(220)

        vim.api.nvim_win_set_buf(0, bufnr)
        vim.api.nvim_win_set_height(0, 18)
        vim.api.nvim_win_set_cursor(0, { 179, 0 })
        vim.fn.winrestview({ topline = 170 })

        local opts = {
            respect_scrolloff = false,
            frames = {
                { row = 129 },
                { row = 130 },
                { row = 173 },
            },
        }

        window.attach(0, opts)
        assert.are.equal(129, vim.fn.winsaveview().topline)
        assert.are.same({
            { start_row = 131, end_row = 171 },
        }, window.state().last_plan.hidden_ranges)

        window.refresh(0, opts)

        assert.are.equal(129, vim.fn.winsaveview().topline)
        assert.are.same({
            { start_row = 131, end_row = 171 },
        }, window.state().last_plan.hidden_ranges)

        vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('preserves the logical viewport across synthetic scroll refreshes', function()
        local bufnr = line_buffer(140)

        vim.api.nvim_win_set_buf(0, bufnr)
        vim.api.nvim_win_set_height(0, 18)
        vim.api.nvim_win_set_cursor(0, { 104, 0 })
        vim.wo.scrolloff = 5
        vim.fn.winrestview({ topline = 92 })

        local opts = {
            frames = {
                { row = 71 },
                { row = 72 },
                { row = 76 },
                { row = 77 },
                { row = 81 },
                { row = 82 },
            },
        }
        local expected_ranges = {
            { start_row = 73, end_row = 75 },
            { start_row = 78, end_row = 80 },
            { start_row = 83, end_row = 97 },
        }

        window.attach(0, opts)
        assert.are.same(expected_ranges, window.state().last_plan.hidden_ranges)
        assert.are.equal(71, vim.fn.winsaveview().topline)

        vim.fn.winrestview({ topline = 73 })
        window.refresh(0, opts)
        assert.are.equal(71, vim.fn.winsaveview().topline)
        assert.are.same(expected_ranges, window.state().last_plan.hidden_ranges)

        vim.fn.winrestview({ topline = 95 })
        window.refresh(0, opts)
        assert.are.equal(71, vim.fn.winsaveview().topline)
        assert.are.same(expected_ranges, window.state().last_plan.hidden_ranges)

        vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('uses the scrolloff-adjusted logical viewport for initial context stitching', function()
        local bufnr = line_buffer(140)

        vim.api.nvim_win_set_buf(0, bufnr)
        vim.api.nvim_win_set_height(0, 18)
        vim.api.nvim_win_set_cursor(0, { 104, 0 })
        vim.wo.scrolloff = 5
        vim.fn.winrestview({ topline = 90 })

        window.attach(0, {
            frames = {
                { row = 71, type = 'namespace_definition' },
                { row = 72, type = 'declaration_list' },
                { row = 76, type = 'function_definition' },
                { row = 77, type = 'compound_statement' },
                { row = 81, type = 'while_statement' },
                { row = 82, type = 'compound_statement' },
            },
        })

        assert.are.equal(71, vim.fn.winsaveview().topline)
        assert.are.same({
            { start_row = 73, end_row = 75 },
            { start_row = 78, end_row = 80 },
            { start_row = 83, end_row = 97 },
        }, window.state().last_plan.hidden_ranges)

        vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('skips a bare compound context row when its owner header is not displayed', function()
        local bufnr = line_buffer(220)

        vim.api.nvim_win_set_buf(0, bufnr)
        vim.api.nvim_win_set_height(0, 18)
        vim.api.nvim_win_set_cursor(0, { 199, 0 })
        vim.fn.winrestview({ topline = 190 })

        window.attach(0, {
            respect_scrolloff = false,
            frames = {
                { row = 129, type = 'linkage_specification' },
                { row = 129, type = 'function_definition' },
                { row = 130, type = 'compound_statement' },
                { row = 173, type = 'compound_statement' },
            },
        })

        assert.are.equal(129, vim.fn.winsaveview().topline)
        assert.are.same({
            { start_row = 131, end_row = 189 },
        }, window.state().last_plan.hidden_ranges)

        vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('keeps adjacent linewise movement on adjacent physical rows', function()
        local bufnr = line_buffer(40)

        vim.api.nvim_win_set_buf(0, bufnr)
        vim.api.nvim_win_set_height(0, 8)
        vim.api.nvim_win_set_cursor(0, { 5, 0 })
        vim.fn.winrestview({ topline = 1 })

        window.attach(0, {
            respect_scrolloff = false,
            frames = {
                { row = 1 },
                { row = 3 },
            },
        })

        local initial_winline = vim.fn.winline()
        assert.are.equal(5, initial_winline)

        vim.api.nvim_win_set_cursor(0, { 6, 0 })
        window.refresh(0, {
            respect_scrolloff = false,
            frames = {
                { row = 1 },
                { row = 4 },
            },
        })

        local state = window.state()

        assert.are.equal(initial_winline + 1, vim.fn.winline())
        assert.are.same({ 1, 4, 6 }, state.last_plan.protected_rows)

        local second_winline = vim.fn.winline()

        vim.api.nvim_win_set_cursor(0, { 7, 0 })
        window.refresh(0, {
            respect_scrolloff = false,
            frames = {
                { row = 1 },
                { row = 5 },
            },
        })

        assert.are.equal(second_winline + 1, vim.fn.winline())

        vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('scrolls the view when expanded context would overshoot adjacent movement', function()
        local bufnr = line_buffer(40)

        vim.api.nvim_win_set_buf(0, bufnr)
        vim.api.nvim_win_set_height(0, 8)
        vim.api.nvim_win_set_cursor(0, { 5, 0 })
        vim.fn.winrestview({ topline = 1 })

        window.attach(0, {
            respect_scrolloff = false,
            frames = {
                { row = 1 },
                { row = 3 },
            },
        })

        local initial_winline = vim.fn.winline()

        assert.are.equal(5, initial_winline)

        vim.api.nvim_win_set_cursor(0, { 6, 0 })
        window.refresh(0, {
            respect_scrolloff = false,
            frames = {
                { row = 1 },
                { row = 2 },
                { row = 3 },
                { row = 4 },
            },
        })

        local state = window.state()

        assert.are.equal(initial_winline + 1, vim.fn.winline())
        assert.are.equal(1, vim.fn.winsaveview().topline)
        assert.are.same({ 1, 2, 3, 4, 6 }, state.last_plan.protected_rows)

        vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('clears marks when no context is available', function()
        local bufnr = vim.api.nvim_create_buf(false, true)

        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'one', 'two', 'three' })
        vim.api.nvim_win_set_buf(0, bufnr)
        vim.api.nvim_win_set_cursor(0, { 3, 0 })

        window.attach(0, {
            frames = {
                { row = 1 },
            },
        })
        window.refresh(0, { context_result = { frames = {}, reason = 'no_parser' } })

        local state = window.state()
        assert.are.same({}, vim.api.nvim_buf_get_extmarks(bufnr, state.ns, 0, -1, {}))

        vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
end)
