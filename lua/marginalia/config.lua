---@class marginalia.Config
---@field enabled boolean
---@field auto_attach boolean
---@field context marginalia.ContextConfig
---@field viewport marginalia.ViewportConfig
---@field render marginalia.RenderConfig
---@field input marginalia.InputConfig

---@class marginalia.ContextConfig
---@field max_depth integer
---@field skip_node_types table<string, boolean>

---@class marginalia.ViewportConfig
---@field respect_scrolloff boolean
---@field scope 'above_cursor'|'full_buffer'

---@class marginalia.RenderConfig
---@field conceallevel integer
---@field priority integer

---@class marginalia.InputConfig
---@field mouse_scroll boolean

local M = {}

---@type marginalia.Config
M.defaults = {
    enabled = true,
    auto_attach = true,
    context = {
        max_depth = 4,
        skip_node_types = {
            block_comment = true,
            chunk = true,
            comment = true,
            normal_command = true,
            preproc_include = true,
            program = true,
            source_file = true,
        },
    },
    viewport = {
        respect_scrolloff = true,
        scope = 'above_cursor',
    },
    render = {
        conceallevel = 2,
        priority = 200,
    },
    input = {
        mouse_scroll = true,
    },
}

---@param values? string[]|table<string, boolean>
---@return table<string, boolean>
local function normalize_type_set(values)
    local result = {}

    for key, value in pairs(values or {}) do
        if type(key) == 'number' then
            result[value] = true
        elseif value then
            result[key] = true
        end
    end

    return result
end

---@param opts? marginalia.Config
---@return marginalia.Config
function M.normalize(opts)
    local config = vim.tbl_deep_extend('force', vim.deepcopy(M.defaults), opts or {})

    if type(config.context) ~= 'table' then
        config.context = vim.deepcopy(M.defaults.context)
    end

    if type(config.viewport) ~= 'table' then
        config.viewport = vim.deepcopy(M.defaults.viewport)
    end

    if type(config.render) ~= 'table' then
        config.render = vim.deepcopy(M.defaults.render)
    end

    if type(config.input) ~= 'table' then
        config.input = vim.deepcopy(M.defaults.input)
    end

    config.context.skip_node_types = normalize_type_set(config.context.skip_node_types)

    if type(config.context.max_depth) ~= 'number' or config.context.max_depth < 0 then
        config.context.max_depth = M.defaults.context.max_depth
    end

    config.context.max_depth = math.floor(config.context.max_depth)
    config.enabled = config.enabled ~= false
    config.auto_attach = config.auto_attach ~= false
    config.input.mouse_scroll = config.input.mouse_scroll ~= false
    config.viewport.respect_scrolloff = config.viewport.respect_scrolloff ~= false

    if type(config.render.conceallevel) ~= 'number' or config.render.conceallevel < 0 then
        config.render.conceallevel = M.defaults.render.conceallevel
    end

    if type(config.render.priority) ~= 'number' then
        config.render.priority = M.defaults.render.priority
    end

    if config.viewport.scope ~= 'full_buffer' then
        config.viewport.scope = 'above_cursor'
    end

    return config
end

return M
