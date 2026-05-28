local M = {}

---@class marginalia.WindowSnapshot
---@field winid integer
---@field bufnr integer
---@field cursor_row integer
---@field line_count integer
---@field raw_view table
---@field normalized_view table
---@field native_winline integer
---@field winheight integer
---@field wrap boolean
---@field window_scrolloff integer
---@field global_scrolloff integer
---@field jumplist marginalia.WindowJumplistSnapshot

---@param winid integer
---@return table
function M.normalized_view(winid)
    vim.fn.line('w0', winid)
    vim.fn.line('.', winid)
    return vim.fn.winsaveview()
end

---@class marginalia.WindowJumplistSnapshot
---@field index integer
---@field length integer
---@field current? table

---@return marginalia.WindowJumplistSnapshot
local function jumplist_snapshot()
    local raw = vim.fn.getjumplist()
    local items = raw[1] or {}
    local index = raw[2] or 0

    return {
        index = index,
        length = #items,
        current = items[index],
    }
end

---@param winid integer
---@return marginalia.WindowSnapshot
function M.capture(winid)
    local bufnr = vim.api.nvim_win_get_buf(winid)

    return {
        winid = winid,
        bufnr = bufnr,
        cursor_row = vim.api.nvim_win_get_cursor(winid)[1],
        line_count = vim.api.nvim_buf_line_count(bufnr),
        raw_view = vim.fn.winsaveview(),
        normalized_view = M.normalized_view(winid),
        native_winline = vim.fn.winline(),
        winheight = vim.api.nvim_win_get_height(winid),
        wrap = vim.wo[winid].wrap,
        window_scrolloff = vim.wo[winid].scrolloff,
        global_scrolloff = vim.go.scrolloff,
        jumplist = jumplist_snapshot(),
    }
end

return M
