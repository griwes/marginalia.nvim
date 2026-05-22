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

describe('marginalia.context', function()
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

        local frames = context.collect_ancestors(leaf, { skip_node_types = { chunk = true } })

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
            {
                type = 'call_expression',
                depth = 3,
                range = { start_row = 6, start_col = 8, end_row = 6, end_col = 20 },
                row = 6,
            },
        }, frames)
    end)

    it('keeps the innermost frames when max_depth applies', function()
        local outer = fake_node({ type = 'outer', range = { 0, 0, 9, 0 } })
        local middle = fake_node({ type = 'middle', range = { 1, 0, 8, 0 }, parent = outer })
        local inner = fake_node({ type = 'inner', range = { 2, 0, 7, 0 }, parent = middle })

        local frames = context.collect_ancestors(inner, { max_depth = 2 })

        assert.are.same({ 'middle', 'inner' }, { frames[1].type, frames[2].type })
        assert.are.equal(1, frames[1].depth)
        assert.are.equal(2, frames[2].depth)
    end)

    it('skips unnamed and configured node types', function()
        local root = fake_node({ type = 'root', range = { 0, 0, 9, 0 } })
        local ignored = fake_node({ type = 'ignored', range = { 1, 0, 8, 0 }, parent = root })
        local unnamed = fake_node({ type = 'anonymous', range = { 2, 0, 7, 0 }, parent = ignored, named = false })
        local leaf = fake_node({ type = 'leaf', range = { 3, 0, 6, 0 }, parent = unnamed })

        local frames = context.collect_ancestors(leaf, { skip_node_types = { ignored = true } })

        assert.are.same({ 'root', 'leaf' }, { frames[1].type, frames[2].type })
    end)

    it('handles nil nodes', function()
        assert.are.same({}, context.collect_ancestors(nil))
    end)
end)
