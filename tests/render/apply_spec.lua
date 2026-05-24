local render_apply = require('marginalia.render.apply')

describe('marginalia.render.apply', function()
    it('applies and restores window options from render plans', function()
        local winid = vim.api.nvim_get_current_win()
        local previous_scrolloff = vim.wo[winid].scrolloff
        local previous_conceallevel = vim.wo[winid].conceallevel

        vim.wo[winid].scrolloff = 4
        vim.wo[winid].conceallevel = 0

        local state = {
            winid = winid,
            options = {
                original_conceallevel = vim.wo[winid].conceallevel,
                conceallevel_applied = false,
                original_scrolloff = vim.wo[winid].scrolloff,
                original_global_scrolloff = vim.go.scrolloff,
                scrolloff_restore_global = false,
                scrolloff_suppressed = false,
            },
            transaction = {},
        }

        render_apply.apply_window_options(state, {
            hidden_ranges = {
                { start_row = 1, end_row = 1 },
            },
        }, 2)

        assert.is_true(state.options.scrolloff_suppressed)
        assert.is_true(state.options.conceallevel_applied)
        assert.are.equal(0, vim.wo[winid].scrolloff)
        assert.are.equal(2, vim.wo[winid].conceallevel)

        render_apply.apply_window_options(state, {
            hidden_ranges = {},
        }, 2)

        assert.is_false(state.options.scrolloff_suppressed)
        assert.is_false(state.options.conceallevel_applied)
        assert.are.equal(4, vim.wo[winid].scrolloff)
        assert.are.equal(0, vim.wo[winid].conceallevel)

        vim.wo[winid].scrolloff = previous_scrolloff
        vim.wo[winid].conceallevel = previous_conceallevel
    end)
end)
