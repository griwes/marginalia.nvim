---@class marginalia.Config
---@field enabled boolean
---@field auto_attach boolean
---@field max_depth integer
---@field skip_node_types table<string, boolean>
---@field conceallevel integer
---@field priority integer
---@field respect_scrolloff boolean
---@field scope 'above_cursor'|'full_buffer'

local M = {}

---@type marginalia.Config
M.defaults = {
    enabled = true,
    auto_attach = true,
    max_depth = 4,
    conceallevel = 2,
    priority = 200,
    respect_scrolloff = true,
    scope = 'above_cursor',
    skip_node_types = {
        chunk = true,
        program = true,
        source_file = true,
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
    local config = vim.tbl_deep_extend('force', M.defaults, opts or {})
    config.skip_node_types = normalize_type_set(config.skip_node_types)

    if type(config.max_depth) ~= 'number' or config.max_depth < 0 then
        config.max_depth = M.defaults.max_depth
    end

    config.max_depth = math.floor(config.max_depth)
    config.enabled = config.enabled ~= false
    config.auto_attach = config.auto_attach ~= false
    config.respect_scrolloff = config.respect_scrolloff ~= false

    if type(config.conceallevel) ~= 'number' or config.conceallevel < 0 then
        config.conceallevel = M.defaults.conceallevel
    end

    if type(config.priority) ~= 'number' then
        config.priority = M.defaults.priority
    end

    if config.scope ~= 'full_buffer' then
        config.scope = 'above_cursor'
    end

    return config
end

return M
