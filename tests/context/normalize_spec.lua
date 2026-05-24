local normalize = require('marginalia.context.normalize')

describe('marginalia.context.normalize', function()
    local function semantic_frame(frame, capture)
        frame.query = { captures = { [capture] = true } }
        return frame
    end

    it('keeps innermost frames when max_depth applies', function()
        local frames = normalize.frames({
            { row = 1, type = 'outer' },
            { row = 10, type = 'middle' },
            { row = 20, type = 'inner' },
        }, {
            context = {
                max_depth = 2,
            },
        })

        assert.are.same({
            { row = 10, type = 'middle', depth = 1 },
            { row = 20, type = 'inner', depth = 2 },
        }, frames)
    end)

    it('builds height-aware viewport candidates from ranges', function()
        local candidates = normalize.candidates({
            {
                type = 'outer',
                source = 'query',
                query = { captures = { context = true } },
                range = {
                    start_row = 3,
                    start_col = 0,
                    end_row = 6,
                    end_col = 0,
                },
            },
            { row = 10, type = 'inner' },
        }, 11)

        assert.are.equal(2, #candidates)
        assert.are.equal(3, candidates[1].source_row)
        assert.are.equal(5, candidates[1].end_row)
        assert.are.same({ 3, 4, 5 }, candidates[1].rows)
        assert.are.equal(3, candidates[1].height)
        assert.are.equal(1, candidates[1].outer_rank)
        assert.are.equal(2, candidates[1].inner_rank)
        assert.are.equal('outer', candidates[1].frame_type)
        assert.are.equal('query', candidates[1].source)
        assert.are.same({ captures = { context = true } }, candidates[1].query)
        assert.are.equal(10, candidates[2].source_row)
        assert.are.equal(1, candidates[2].height)
        assert.are.equal('ancestor', candidates[2].source)
    end)

    it('does not include candidate rows at or below the cursor', function()
        local candidates = normalize.candidates({
            {
                type = 'outer',
                range = {
                    start_row = 3,
                    start_col = 0,
                    end_row = 8,
                    end_col = 0,
                },
            },
        }, 5)

        assert.are.same({ 3, 4 }, candidates[1].rows)
        assert.are.equal(2, candidates[1].height)
    end)

    it('filters non-renderable bare compound rows', function()
        local frames = normalize.renderable_frames({
            { row = 1, type = 'namespace' },
            semantic_frame({ row = 10, type = 'compound_statement' }, 'context.body.compound'),
            { row = 11, type = 'function_definition' },
            semantic_frame({ row = 12, type = 'compound_statement' }, 'context.body.compound'),
        })

        assert.are.same({
            { row = 1, type = 'namespace' },
            { row = 11, type = 'function_definition' },
            semantic_frame({ row = 12, type = 'compound_statement' }, 'context.body.compound'),
        }, frames)
    end)

    it('trims outer context rows while preserving innermost visible rows', function()
        local frames = {
            { row = 1, type = 'namespace' },
            {
                type = 'function_definition',
                range = {
                    start_row = 10,
                    start_col = 0,
                    end_row = 14,
                    end_col = 0,
                },
            },
            { row = 20, type = 'inner' },
        }

        normalize.trim_outer_rows(frames, 3)

        assert.are.same({
            {
                type = 'function_definition',
                range = {
                    start_row = 10,
                    start_col = 0,
                    end_row = 12,
                    end_col = 0,
                },
            },
            { row = 20, type = 'inner' },
        }, frames)
    end)

    it('derives header facts for language-specific context frames', function()
        local completed_function = normalize.frame_header_facts({
            type = 'function_definition',
            range = {
                start_row = 10,
                start_col = 4,
                end_row = 13,
                end_col = 0,
            },
            query = { captures = { ['context.header.function'] = true } },
        }, 14)

        assert.is_true(completed_function.multiline_function_header)
        assert.is_true(completed_function.completed_function_header)
        assert.is_false(completed_function.in_progress_function_header)

        local final_function_line = normalize.frame_header_facts(
            {
                type = 'function_definition',
                range = {
                    start_row = 10,
                    start_col = 4,
                    end_row = 13,
                    end_col = 0,
                },
                query = { captures = { ['context.header.function'] = true } },
            },
            12,
            {
                stitch = {
                    floor = 10,
                },
            }
        )

        assert.is_true(final_function_line.final_function_header_line)

        local struct_header = normalize.frame_header_facts({
            type = 'class_specifier',
            range = {
                start_row = 20,
                start_col = 0,
                end_row = 23,
                end_col = 0,
            },
            query = { captures = { ['context.header.struct'] = true } },
        }, 21)

        assert.is_true(struct_header.cursor_on_struct_header)
        assert.is_false(struct_header.completed_struct_header)
    end)

    it('identifies disconnected compound context rows', function()
        assert.is_true(normalize.is_disconnected_compound_context({
            type = 'compound_statement',
            query = { captures = { ['context.body.compound'] = true } },
        }, 10, 5))
        assert.is_false(normalize.is_disconnected_compound_context({
            type = 'compound_statement',
            query = { captures = { ['context.body.compound'] = true } },
        }, 6, 5))
        assert.is_false(normalize.is_disconnected_compound_context({
            type = 'function_definition',
        }, 10, 5))
    end)

    it('queries renderable frame start-row facts', function()
        local frames = {
            { row = 1, type = 'namespace' },
            semantic_frame({ row = 10, type = 'compound_statement' }, 'context.body.compound'),
            { row = 11, type = 'function_definition' },
            semantic_frame({ row = 12, type = 'compound_statement' }, 'context.body.compound'),
            { row = 30, type = 'class_specifier' },
        }

        assert.are.equal(12, normalize.nearest_start_row_before(frames, 20))
        assert.is_true(normalize.has_start_row(frames, 11))
        assert.is_false(normalize.has_start_row(frames, 10))
        assert.is_true(normalize.has_start_row_at_or_after(frames, 12))
        assert.is_false(normalize.has_start_row_at_or_after(frames, 31))
        assert.is_true(normalize.has_start_row_in_range(frames, 11, 12))
        assert.is_false(normalize.has_start_row_in_range(frames, 9, 10))
    end)
end)
