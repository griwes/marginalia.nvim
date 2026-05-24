local context = require('marginalia.context')

---@param spec table
---@return table
local function fake_node(spec)
    spec.children = spec.children or {}

    local node = {}

    function node:type()
        return spec.type
    end

    function node:range()
        return spec.range[1], spec.range[2], spec.range[3], spec.range[4]
    end

    function node:named()
        return spec.named ~= false
    end

    function node:parent()
        return spec.parent
    end

    function node:iter_children()
        local index = 0

        return function()
            index = index + 1
            return spec.children[index]
        end
    end

    for _, child in ipairs(spec.children) do
        child.__spec.parent = node
    end

    node.__spec = spec

    return node
end

---@param spec table
---@return table
local function node_tree(spec)
    local children = {}

    for _, child_spec in ipairs(spec.children or {}) do
        children[#children + 1] = node_tree(child_spec)
    end

    spec.children = children

    return fake_node(spec)
end

---@param captured table<string, boolean>
---@return table
local function fake_context_query(captured)
    return {
        captures = { 'context' },
        iter_matches = function(_, node)
            local yielded = false

            return function()
                if yielded or not captured[node:type()] then
                    return nil
                end

                yielded = true
                return 1, { [1] = node }
            end
        end,
    }
end

---@param specs table<string, table[]>
---@return table
local function fake_context_query_with_captures(specs)
    local capture_ids = {
        context = 1,
        ['context.start'] = 2,
        ['context.final'] = 3,
        ['context.end'] = 4,
        ['context.header.function'] = 5,
        ['context.header.struct'] = 6,
        ['context.body.compound'] = 7,
    }

    return {
        captures = {
            [capture_ids.context] = 'context',
            [capture_ids['context.start']] = 'context.start',
            [capture_ids['context.final']] = 'context.final',
            [capture_ids['context.end']] = 'context.end',
            [capture_ids['context.header.function']] = 'context.header.function',
            [capture_ids['context.header.struct']] = 'context.header.struct',
            [capture_ids['context.body.compound']] = 'context.body.compound',
        },
        iter_matches = function(_, node)
            local yielded = false

            return function()
                if yielded then
                    return nil
                end

                local captures = specs[node:type()]

                if not captures then
                    return nil
                end

                local match = {}

                for _, capture in ipairs(captures) do
                    match[capture_ids[capture.name]] = capture.node or node
                end

                yielded = true
                return 1, match
            end
        end,
    }
end

describe('marginalia.context collect', function()
    it('collects named ancestors from outermost to innermost', function()
        local root = node_tree({
            type = 'chunk',
            range = { 0, 0, 20, 0 },
            children = {
                {
                    type = 'function_declaration',
                    range = { 1, 0, 10, 3 },
                    children = {
                        {
                            type = 'if_statement',
                            range = { 3, 4, 8, 7 },
                            children = {
                                {
                                    type = 'call_expression',
                                    range = { 5, 8, 5, 20 },
                                },
                            },
                        },
                    },
                },
            },
        })
        local leaf = root.__spec.children[1].__spec.children[1].__spec.children[1]

        local frames = context.collect_ancestors(leaf, {
            context = {
                skip_node_types = { chunk = true },
            },
        })

        assert.are.same({
            {
                type = 'function_declaration',
                depth = 1,
                range = { start_row = 2, start_col = 0, end_row = 11, end_col = 3 },
                row = 2,
            },
            {
                type = 'if_statement',
                depth = 2,
                range = { start_row = 4, start_col = 4, end_row = 9, end_col = 7 },
                row = 4,
            },
        }, frames)
    end)

    it('keeps the innermost frames when max_depth applies', function()
        local outer = fake_node({ type = 'outer', range = { 0, 0, 9, 0 } })
        local middle = fake_node({ type = 'middle', range = { 1, 0, 8, 0 }, parent = outer })
        local inner = fake_node({ type = 'inner', range = { 2, 0, 7, 0 }, parent = middle })

        local frames = context.collect_ancestors(inner, {
            context = {
                max_depth = 2,
            },
        })

        assert.are.same({ 'middle', 'inner' }, { frames[1].type, frames[2].type })
        assert.are.equal(1, frames[1].depth)
        assert.are.equal(2, frames[2].depth)
    end)

    it('skips unnamed and configured node types', function()
        local root = fake_node({ type = 'root', range = { 0, 0, 9, 0 } })
        local ignored = fake_node({ type = 'ignored', range = { 1, 0, 8, 0 }, parent = root })
        local unnamed = fake_node({ type = 'anonymous', range = { 2, 0, 7, 0 }, parent = ignored, named = false })
        local leaf = fake_node({ type = 'leaf', range = { 3, 0, 6, 0 }, parent = unnamed })

        local frames = context.collect_ancestors(leaf, {
            context = {
                skip_node_types = { ignored = true },
            },
        })

        assert.are.same({ 'root', 'leaf' }, { frames[1].type, frames[2].type })
    end)

    it('skips comment nodes by default', function()
        local comment = fake_node({ type = 'comment', range = { 0, 0, 14, 3 } })

        local frames = context.collect_ancestors(comment)

        assert.are.same({}, frames)
    end)

    it('skips block comment nodes by default', function()
        local comment = fake_node({ type = 'block_comment', range = { 0, 0, 14, 3 } })

        local frames = context.collect_ancestors(comment)

        assert.are.same({}, frames)
    end)

    it('skips preprocessor include nodes by default', function()
        local include = fake_node({ type = 'preproc_include', range = { 16, 0, 17, 0 } })

        local frames = context.collect_ancestors(include)

        assert.are.same({}, frames)
    end)

    it('skips single-line nodes by default', function()
        local command = fake_node({ type = 'normal_command', range = { 13, 0, 13, 76 } })

        local frames = context.collect_ancestors(command)

        assert.are.same({}, frames)
    end)

    it('skips multiline CMake command nodes by default', function()
        local command = fake_node({ type = 'normal_command', range = { 372, 8, 373, 1 } })

        local frames = context.collect_ancestors(command)

        assert.are.same({}, frames)
    end)

    it('uses context query captures instead of generic ancestors when available', function()
        local root = node_tree({
            type = 'source_file',
            range = { 0, 0, 120, 0 },
            children = {
                {
                    type = 'if_condition',
                    range = { 74, 0, 119, 0 },
                    children = {
                        {
                            type = 'body',
                            range = { 75, 0, 118, 0 },
                            children = {
                                {
                                    type = 'foreach_loop',
                                    range = { 82, 0, 117, 0 },
                                    children = {
                                        {
                                            type = 'body',
                                            range = { 83, 0, 116, 0 },
                                            children = {
                                                {
                                                    type = 'normal_command',
                                                    range = { 87, 0, 96, 1 },
                                                    children = {
                                                        {
                                                            type = 'argument_list',
                                                            range = { 87, 4, 96, 1 },
                                                            children = {
                                                                {
                                                                    type = 'argument',
                                                                    range = { 89, 8, 94, 1 },
                                                                },
                                                            },
                                                        },
                                                    },
                                                },
                                            },
                                        },
                                    },
                                },
                            },
                        },
                    },
                },
            },
        })
        local leaf =
            root.__spec.children[1].__spec.children[1].__spec.children[1].__spec.children[1].__spec.children[1].__spec.children[1].__spec.children[1]

        local frames = context.collect_ancestors(leaf, {
            context_query = fake_context_query({
                if_condition = true,
                foreach_loop = true,
                normal_command = true,
            }),
            context = {
                skip_node_types = { normal_command = false },
            },
        })

        assert.are.same({
            {
                type = 'if_condition',
                depth = 1,
                range = { start_row = 75, start_col = 0, end_row = 76, end_col = 0 },
                row = 75,
                source = 'query',
                query = { captures = { context = true } },
            },
            {
                type = 'foreach_loop',
                depth = 2,
                range = { start_row = 83, start_col = 0, end_row = 84, end_col = 0 },
                row = 83,
                source = 'query',
                query = { captures = { context = true } },
            },
            {
                type = 'normal_command',
                depth = 3,
                range = { start_row = 88, start_col = 0, end_row = 89, end_col = 0 },
                row = 88,
                source = 'query',
                query = { captures = { context = true } },
            },
        }, frames)
    end)

    it('keeps query-captured struct specifiers as active context', function()
        local specifier = fake_node({ type = 'struct_specifier', range = { 26, 4, 40, 6 } })

        local frames = context.collect_ancestors(specifier, {
            context_query = fake_context_query({
                struct_specifier = true,
            }),
        })

        assert.are.same({
            {
                type = 'struct_specifier',
                depth = 1,
                range = { start_row = 27, start_col = 4, end_row = 28, end_col = 0 },
                row = 27,
                source = 'query',
                query = { captures = { context = true } },
            },
        }, frames)
    end)

    it('trims context.end ranges to the visible multiline header', function()
        local bufnr = vim.api.nvim_create_buf(false, true)

        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
            'namespace demo',
            '{',
            '    void run()',
            '    {',
            '        call();',
            '    }',
            '}',
        })

        local root = node_tree({
            type = 'source_file',
            range = { 0, 0, 7, 0 },
            children = {
                {
                    type = 'namespace_definition',
                    range = { 0, 0, 6, 1 },
                    children = {
                        {
                            type = 'function_definition',
                            range = { 2, 4, 5, 5 },
                            children = {
                                {
                                    type = 'compound_statement',
                                    range = { 3, 4, 5, 5 },
                                    children = {
                                        {
                                            type = 'expression_statement',
                                            range = { 4, 8, 4, 15 },
                                        },
                                    },
                                },
                            },
                        },
                    },
                },
            },
        })
        local function_node = root.__spec.children[1].__spec.children[1]
        local leaf = function_node.__spec.children[1].__spec.children[1]
        local query = fake_context_query_with_captures({
            function_definition = {
                { name = 'context' },
                { name = 'context.end', node = leaf },
            },
        })

        local frames = context.collect_ancestors(leaf, {
            bufnr = bufnr,
            context_query = query,
        })

        assert.are.same({
            {
                type = 'function_definition',
                depth = 1,
                range = { start_row = 3, start_col = 4, end_row = 5, end_col = 0 },
                row = 3,
                source = 'query',
                query = { captures = { context = true, ['context.end'] = true } },
            },
        }, frames)
    end)

    it('records query semantic captures on frames', function()
        local function_node = fake_node({ type = 'function_definition', range = { 2, 4, 5, 5 } })
        local query = fake_context_query_with_captures({
            function_definition = {
                { name = 'context' },
                { name = 'context.header.function' },
            },
        })

        local frames = context.collect_ancestors(function_node, {
            context_query = query,
        })

        assert.are.same({
            context = true,
            ['context.header.function'] = true,
        }, frames[1].query.captures)
    end)

    it('records query semantics for compound body context', function()
        local compound_node = fake_node({ type = 'compound_statement', range = { 3, 4, 5, 5 } })
        local query = fake_context_query_with_captures({
            compound_statement = {
                { name = 'context' },
                { name = 'context.body.compound' },
            },
        })

        local frames = context.collect_ancestors(compound_node, {
            context_query = query,
        })

        assert.are.same({
            context = true,
            ['context.body.compound'] = true,
        }, frames[1].query.captures)
    end)

    it('handles nil nodes', function()
        assert.are.same({}, context.collect_ancestors(nil))
    end)
end)
