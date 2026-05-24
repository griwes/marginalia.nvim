local render_derive = require('marginalia.render.derive')
local render_provider = require('marginalia.render.provider')

local M = {}

---@param opts { bufnr: integer, state: marginalia.WindowState, projection: marginalia.ViewportProjection, priority?: integer }
---@return { visible_rows: integer[], hidden_ranges: marginalia.HiddenRange[], projection: marginalia.ViewportProjection }
function M.apply_projection(opts)
    local plan = render_derive.from_projection(opts.projection)

    plan.projection = opts.projection
    render_provider.update_window(opts.state, plan.hidden_ranges, {
        priority = opts.priority,
    })

    return plan
end

return M
