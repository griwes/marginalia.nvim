local renderer = require('marginalia.renderer')

describe('marginalia.renderer', function()
    it('applies conceal-line extmarks for hidden ranges', function()
        local bufnr = vim.api.nvim_create_buf(false, true)
        local ns = renderer.namespace('test.apply')

        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'one', 'two', 'three', 'four' })
        renderer.apply(bufnr, ns, {
            { start_row = 1, end_row = 2 },
            { start_row = 4, end_row = 4 },
        })

        local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })

        assert.are.equal(2, #marks)
        assert.are.equal('', marks[1][4].conceal_lines)
        assert.are.equal('', marks[2][4].conceal_lines)
        assert.are.equal(0, marks[1][2])
        assert.are.equal(1, marks[1][4].end_row)
        assert.are.equal(3, marks[2][2])
        assert.are.equal(3, marks[2][4].end_row)

        vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('clears stale extmarks before applying a new plan', function()
        local bufnr = vim.api.nvim_create_buf(false, true)
        local ns = renderer.namespace('test.clear')

        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'one', 'two', 'three' })
        renderer.apply(bufnr, ns, {
            { start_row = 1, end_row = 1 },
        })
        renderer.apply(bufnr, ns, {})

        assert.are.same({}, vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {}))

        vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('leaves the row after a hidden range visible on screen', function()
        local bufnr = vim.api.nvim_create_buf(false, true)
        local ns = renderer.namespace('test.visible-tail')
        local previous_bufnr = vim.api.nvim_get_current_buf()
        local previous_conceallevel = vim.wo.conceallevel

        vim.api.nvim_set_current_buf(bufnr)
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'one', 'two', 'three', 'four', 'five' })
        vim.wo.conceallevel = 2

        renderer.apply(bufnr, ns, {
            { start_row = 2, end_row = 3 },
        })

        vim.cmd.redraw()

        assert.are.equal('one', vim.fn.screenstring(1, 1) .. vim.fn.screenstring(1, 2) .. vim.fn.screenstring(1, 3))
        assert.are.equal(
            'four',
            vim.fn.screenstring(2, 1)
                .. vim.fn.screenstring(2, 2)
                .. vim.fn.screenstring(2, 3)
                .. vim.fn.screenstring(2, 4)
        )
        assert.are.equal(
            'five',
            vim.fn.screenstring(3, 1)
                .. vim.fn.screenstring(3, 2)
                .. vim.fn.screenstring(3, 3)
                .. vim.fn.screenstring(3, 4)
        )

        vim.wo.conceallevel = previous_conceallevel
        vim.api.nvim_set_current_buf(previous_bufnr)
        vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
end)
