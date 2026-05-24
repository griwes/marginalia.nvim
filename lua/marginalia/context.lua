local collect = require('marginalia.context.collect')
local normalize = require('marginalia.context.normalize')
local source = require('marginalia.context.source')

local M = {}

---@class marginalia.FrameRange
---@field start_row integer
---@field start_col integer
---@field end_row integer
---@field end_col integer

---@class marginalia.ContextFrame
---@field type string
---@field depth integer
---@field range marginalia.FrameRange
---@field row integer
---@field source? 'query'
---@field query? { captures: table<string, true> }

---@class marginalia.ContextResult
---@field frames marginalia.ContextFrame[]
---@field reason? string
---@field stale? boolean

---@param node TSNode?
---@param opts? marginalia.Config
---@return marginalia.ContextFrame[]
function M.collect_ancestors(node, opts)
    return normalize.frames(collect.ancestors(node, opts), opts)
end

---@param opts? marginalia.Config|{ bufnr?: integer, winid?: integer, lang?: string, context?: marginalia.ContextConfig }
---@return marginalia.ContextResult
function M.for_window(opts)
    local result = source.for_window(opts)

    return {
        frames = normalize.frames(result.frames, opts),
        reason = result.reason,
        stale = result.stale,
    }
end

return M
