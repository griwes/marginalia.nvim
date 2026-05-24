local derive = require('marginalia.render.derive')

describe('marginalia.render.derive', function()
    it('returns no hidden ranges for empty inputs', function()
        assert.are.same({}, derive.hidden_ranges({ conceal_start_row = 1, conceal_end_row = 5 }))
    end)

    it('compacts consecutive hidden rows', function()
        local ranges = derive.hidden_ranges({
            conceal_start_row = 1,
            conceal_end_row = 10,
            visible_rows = { 2, 5, 6, 9 },
        })

        assert.are.same({
            { start_row = 1, end_row = 1 },
            { start_row = 3, end_row = 4 },
            { start_row = 7, end_row = 8 },
            { start_row = 10, end_row = 10 },
        }, ranges)
    end)

    it('derives hidden ranges from projection visible rows', function()
        local artifact = derive.from_projection({
            visible_rows = { 1, 4, 5 },
            conceal_scope = {
                start_row = 1,
                end_row = 6,
            },
        })

        assert.are.same({ 1, 4, 5 }, artifact.visible_rows)
        assert.are.same({
            { start_row = 2, end_row = 3 },
            { start_row = 6, end_row = 6 },
        }, artifact.hidden_ranges)
    end)

    it('normalizes duplicate projection rows', function()
        local artifact = derive.from_projection({
            visible_rows = {
                [4] = true,
                [2] = true,
                [5] = true,
            },
            conceal_scope = {
                start_row = 1,
                end_row = 5,
            },
        })

        assert.are.same({ 2, 4, 5 }, artifact.visible_rows)
        assert.are.same({
            { start_row = 1, end_row = 1 },
            { start_row = 3, end_row = 3 },
        }, artifact.hidden_ranges)
    end)
end)
