local collect = require('marginalia.context.collect')

local M = {}

---@class marginalia.ContextTreeCache
---@field bufnr integer
---@field lang? string
---@field changedtick integer
---@field trees table<integer, TSTree>
---@field parser vim.treesitter.LanguageTree
---@field context_query marginalia.ContextQuery?
---@field pending_generation? integer
---@field generation integer

---@type table<string, marginalia.ContextTreeCache>
local cache = {}

---@param bufnr integer
---@param lang? string
---@return string
local function cache_key(bufnr, lang)
    return tostring(bufnr) .. ':' .. (lang or '')
end

---@param bufnr integer
---@return integer
local function changedtick(bufnr)
    return vim.api.nvim_buf_get_changedtick(bufnr)
end

---@param parser vim.treesitter.LanguageTree?
---@param bufnr integer
---@param requested_lang? string
---@return marginalia.ContextQuery?
function M.context_query_for(parser, bufnr, requested_lang)
    local lang = requested_lang

    if not lang and parser and type(parser.lang) == 'function' then
        local ok, parser_lang = pcall(function()
            return parser:lang()
        end)

        if ok then
            lang = parser_lang
        end
    end

    if not lang or lang == '' then
        lang = vim.bo[bufnr].filetype
    end

    if not lang or lang == '' then
        return nil
    end

    local get_query = vim.treesitter.query.get or vim.treesitter.query.get_query
    local ok, query = pcall(get_query, lang, 'context')

    if not ok then
        return nil
    end

    return query
end

---@param opts { bufnr: integer, lang?: string, parser: vim.treesitter.LanguageTree, context_query: marginalia.ContextQuery?, changedtick: integer, on_publish?: fun(bufnr: integer) }
---@return table<integer, TSTree>?
local function request_parse(opts)
    local key = cache_key(opts.bufnr, opts.lang)
    local previous = cache[key]
    local generation = (previous and previous.generation or 0) + 1

    if previous and previous.pending_generation and previous.changedtick == opts.changedtick then
        return nil
    end

    cache[key] = vim.tbl_extend('force', previous or {}, {
        bufnr = opts.bufnr,
        lang = opts.lang,
        parser = opts.parser,
        context_query = opts.context_query,
        changedtick = opts.changedtick,
        pending_generation = generation,
        generation = generation,
    })

    local ok, immediate = pcall(function()
        return opts.parser:parse(nil, function(err, trees)
            vim.schedule(function()
                local current = cache[key]

                if not current or current.pending_generation ~= generation then
                    return
                end

                current.pending_generation = nil

                if err or not trees or not trees[1] then
                    return
                end

                if not vim.api.nvim_buf_is_valid(opts.bufnr) or changedtick(opts.bufnr) ~= opts.changedtick then
                    return
                end

                current.trees = trees
                current.changedtick = opts.changedtick
                current.context_query = opts.context_query

                if opts.on_publish then
                    opts.on_publish(opts.bufnr)
                end
            end)
        end)
    end)

    if not ok then
        return nil
    end

    if immediate and immediate[1] then
        local current = cache[key]
        current.pending_generation = nil
        current.trees = immediate
        current.changedtick = opts.changedtick
        return immediate
    end

    return nil
end

---@param opts? { bufnr?: integer, winid?: integer, lang?: string }
---@return { bufnr: integer, winid: integer, row: integer, col: integer, parser: vim.treesitter.LanguageTree, trees: table<integer, TSTree>, context_query: marginalia.ContextQuery?, stale?: boolean }?, string?
function M.snapshot(opts)
    opts = opts or {}

    local winid = opts.winid or vim.api.nvim_get_current_win()
    local bufnr = opts.bufnr or vim.api.nvim_win_get_buf(winid)
    local cursor = vim.api.nvim_win_get_cursor(winid)
    local row = cursor[1] - 1
    local col = cursor[2]
    local tick = changedtick(bufnr)

    local parser_ok, parser = pcall(vim.treesitter.get_parser, bufnr, opts.lang)

    if not parser_ok or not parser then
        return nil, 'no_parser'
    end

    local lang = opts.lang
    local query = M.context_query_for(parser, bufnr, lang)
    local key = cache_key(bufnr, lang)
    local cached = cache[key]

    if cached and cached.trees and cached.changedtick == tick then
        return {
            bufnr = bufnr,
            winid = winid,
            row = row,
            col = col,
            parser = parser,
            trees = cached.trees,
            context_query = cached.context_query,
        },
            nil
    end

    local trees = request_parse({
        bufnr = bufnr,
        lang = lang,
        parser = parser,
        context_query = query,
        changedtick = tick,
        on_publish = opts.on_publish,
    })

    if trees and trees[1] then
        return {
            bufnr = bufnr,
            winid = winid,
            row = row,
            col = col,
            parser = parser,
            trees = trees,
            context_query = query,
        },
            nil
    end

    if cached and cached.trees then
        return {
            bufnr = bufnr,
            winid = winid,
            row = row,
            col = col,
            parser = parser,
            trees = cached.trees,
            context_query = cached.context_query,
            stale = true,
        },
            nil
    end

    return nil, 'parse_pending'
end

M.snapshot_sync = M.snapshot

---@param opts? { bufnr?: integer, winid?: integer, lang?: string, on_publish?: fun(bufnr: integer) }
---@return marginalia.ContextResult
function M.for_window(opts)
    local snapshot, reason = M.snapshot(opts)

    if not snapshot then
        return { frames = {}, reason = reason }
    end

    local root = snapshot.trees[1]:root()
    local node = collect.innermost_named_node_at(root, snapshot.row, snapshot.col)

    return {
        frames = collect.ancestors(
            node,
            vim.tbl_deep_extend('force', opts or {}, {
                bufnr = snapshot.bufnr,
                context_query = snapshot.context_query,
            })
        ),
        stale = snapshot.stale,
    }
end

M.for_window_sync = M.for_window

function M._reset_for_tests()
    cache = {}
end

return M
