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

---@param winid integer
---@return table
function M.normalized_view(winid)
    vim.fn.line('w0', winid)
    vim.fn.line('.', winid)
    return vim.fn.winsaveview()
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
    }
end

return M
