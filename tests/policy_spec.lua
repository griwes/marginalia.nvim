local policy = require('marginalia.policy')

describe('marginalia.policy', function()
    it('returns no hidden ranges for empty inputs', function()
        assert.are.same({}, policy.hidden_ranges({ start_row = 1, end_row = 5 }))
        assert.are.same({
            protected_rows = {},
            hidden_ranges = {},
        }, policy.plan({ start_row = 1, end_row = 5 }))
    end)

    it('protects context, cursor, and caller-provided rows', function()
        local rows = policy.protected_rows({
            frames = {
                { row = 3 },
                { range = { start_row = 5 } },
            },
            cursor_row = 7,
            protected_rows = { 2, 5 },
        })

        assert.are.same({ 2, 3, 5, 7 }, rows)
    end)

    it('compacts consecutive hidden rows', function()
        local ranges = policy.hidden_ranges({
            start_row = 1,
            end_row = 10,
            protected_rows = { 2, 5, 6, 9 },
        })

        assert.are.same({
            { start_row = 1, end_row = 1 },
            { start_row = 3, end_row = 4 },
            { start_row = 7, end_row = 8 },
            { start_row = 10, end_row = 10 },
        }, ranges)
    end)

    it('builds a complete plan from context frames', function()
        local plan = policy.plan({
            start_row = 1,
            end_row = 6,
            cursor_row = 4,
            frames = {
                { row = 2 },
                { row = 5 },
            },
        })

        assert.are.same({ 2, 4, 5 }, plan.protected_rows)
        assert.are.same({
            { start_row = 1, end_row = 1 },
            { start_row = 3, end_row = 3 },
            { start_row = 6, end_row = 6 },
        }, plan.hidden_ranges)
    end)

    it('normalizes overlapping protected rows', function()
        local plan = policy.plan({
            start_row = 1,
            end_row = 5,
            cursor_row = 3,
            frames = {
                { row = 3 },
            },
            protected_rows = {
                [3] = true,
                [4] = true,
            },
        })

        assert.are.same({ 3, 4 }, plan.protected_rows)
        assert.are.same({
            { start_row = 1, end_row = 2 },
            { start_row = 5, end_row = 5 },
        }, plan.hidden_ranges)
    end)

    it('protects configured row ranges', function()
        local plan = policy.plan({
            start_row = 1,
            end_row = 8,
            protected_ranges = {
                { start_row = 3, end_row = 5 },
            },
        })

        assert.are.same({ 3, 4, 5 }, plan.protected_rows)
        assert.are.same({
            { start_row = 1, end_row = 2 },
            { start_row = 6, end_row = 8 },
        }, plan.hidden_ranges)
    end)
end)
