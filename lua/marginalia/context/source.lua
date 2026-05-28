local collect = require('marginalia.context.collect')

local M = {}

---@class marginalia.ContextTreeCache
---@field bufnr integer
---@field lang string
---@field changedtick integer
---@field trees? table<integer, TSTree>
---@field parser vim.treesitter.LanguageTree
---@field pending_generation? integer
---@field generation integer
---@field subscribers table<any, fun(bufnr: integer)>

---@type table<string, marginalia.ContextTreeCache>
local cache = {}

---@param bufnr integer
---@param lang string
---@return string
local function cache_key(bufnr, lang)
    return tostring(bufnr) .. ':' .. lang
end

---@param bufnr integer
---@return integer
local function changedtick(bufnr)
    return vim.api.nvim_buf_get_changedtick(bufnr)
end

---@param parser vim.treesitter.LanguageTree?
---@param fallback? string
---@return string?
local function parser_lang(parser, fallback)
    if parser and type(parser.lang) == 'function' then
        local ok, lang = pcall(function()
            return parser:lang()
        end)

        if ok and type(lang) == 'string' and lang ~= '' then
            return lang
        end
    end

    if type(fallback) == 'string' and fallback ~= '' then
        return fallback
    end

    return nil
end

---@param row integer
---@param col integer
---@return integer[]
local function cursor_range(row, col)
    return { row, col, row, col }
end

---@param parser vim.treesitter.LanguageTree
---@param row integer
---@param col integer
---@return vim.treesitter.LanguageTree
local function language_tree_at(parser, row, col)
    if type(parser.language_for_range) ~= 'function' then
        return parser
    end

    local ok, language_tree = pcall(parser.language_for_range, parser, cursor_range(row, col))

    if ok and language_tree then
        return language_tree
    end

    return parser
end

---@param language_tree vim.treesitter.LanguageTree
---@param fallback table<integer, TSTree>
---@return table<integer, TSTree>
local function language_trees(language_tree, fallback)
    if type(language_tree.trees) == 'function' then
        local ok, trees = pcall(language_tree.trees, language_tree)

        if ok and trees and trees[1] then
            return trees
        end
    end

    return fallback
end

---@param parser vim.treesitter.LanguageTree?
---@param bufnr integer
---@param requested_lang? string
---@return marginalia.ContextQuery?
function M.context_query_for(parser, bufnr, requested_lang)
    local lang = parser_lang(parser, requested_lang)

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

---@param entry marginalia.ContextTreeCache
---@param key any
---@param callback? fun(bufnr: integer)
local function subscribe(entry, key, callback)
    if not callback then
        return
    end

    entry.subscribers[key or callback] = callback
end

---@param opts { bufnr: integer, lang: string, parser: vim.treesitter.LanguageTree, changedtick: integer, subscriber_key?: any, on_publish?: fun(bufnr: integer) }
---@return table<integer, TSTree>?
local function request_parse(opts)
    local key = cache_key(opts.bufnr, opts.lang)
    local previous = cache[key]

    if
        previous
        and previous.parser == opts.parser
        and previous.pending_generation
        and previous.changedtick == opts.changedtick
    then
        subscribe(previous, opts.subscriber_key, opts.on_publish)
        return nil
    end

    local generation = (previous and previous.generation or 0) + 1
    local entry = {
        bufnr = opts.bufnr,
        lang = opts.lang,
        parser = opts.parser,
        changedtick = opts.changedtick,
        pending_generation = generation,
        generation = generation,
        subscribers = {},
    }

    if previous and previous.parser == opts.parser then
        entry.trees = previous.trees
    end

    subscribe(entry, opts.subscriber_key, opts.on_publish)
    cache[key] = entry

    local ok, immediate = pcall(function()
        return opts.parser:parse(nil, function(err, trees)
            vim.schedule(function()
                local current = cache[key]

                if not current or current.pending_generation ~= generation then
                    return
                end

                current.pending_generation = nil

                if err or not trees or not trees[1] then
                    current.subscribers = {}
                    return
                end

                if not vim.api.nvim_buf_is_valid(opts.bufnr) or changedtick(opts.bufnr) ~= opts.changedtick then
                    current.subscribers = {}
                    return
                end

                current.trees = trees
                current.changedtick = opts.changedtick

                local subscribers = current.subscribers
                current.subscribers = {}

                for _, callback in pairs(subscribers) do
                    pcall(callback, opts.bufnr)
                end
            end)
        end)
    end)

    if not ok then
        entry.pending_generation = nil
        entry.subscribers = {}
        return nil
    end

    if immediate and immediate[1] then
        entry.pending_generation = nil
        entry.trees = immediate
        entry.changedtick = opts.changedtick
        entry.subscribers = {}
        return immediate
    end

    return nil
end

---@param opts { bufnr: integer, winid: integer, row: integer, col: integer, parser: vim.treesitter.LanguageTree, trees: table<integer, TSTree>, stale?: boolean }
---@return { bufnr: integer, winid: integer, row: integer, col: integer, parser: vim.treesitter.LanguageTree, trees: table<integer, TSTree>, context_query: marginalia.ContextQuery?, stale?: boolean }
local function resolve_snapshot(opts)
    local language_tree = language_tree_at(opts.parser, opts.row, opts.col)
    local lang = parser_lang(language_tree, parser_lang(opts.parser, vim.bo[opts.bufnr].filetype))

    return {
        bufnr = opts.bufnr,
        winid = opts.winid,
        row = opts.row,
        col = opts.col,
        parser = language_tree,
        trees = language_trees(language_tree, opts.trees),
        context_query = M.context_query_for(language_tree, opts.bufnr, lang),
        stale = opts.stale,
    }
end

---@param opts? { bufnr?: integer, winid?: integer, lang?: string, on_publish?: fun(bufnr: integer) }
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

    local lang = parser_lang(parser, opts.lang or vim.bo[bufnr].filetype)

    if not lang then
        return nil, 'no_parser'
    end

    local key = cache_key(bufnr, lang)
    local cached = cache[key]

    if cached and cached.parser == parser and cached.trees and cached.changedtick == tick then
        return resolve_snapshot({
            bufnr = bufnr,
            winid = winid,
            row = row,
            col = col,
            parser = parser,
            trees = cached.trees,
        }),
            nil
    end

    local trees = request_parse({
        bufnr = bufnr,
        lang = lang,
        parser = parser,
        changedtick = tick,
        subscriber_key = winid,
        on_publish = opts.on_publish,
    })

    if trees and trees[1] then
        return resolve_snapshot({
            bufnr = bufnr,
            winid = winid,
            row = row,
            col = col,
            parser = parser,
            trees = trees,
        }),
            nil
    end

    if cached and cached.parser == parser and cached.trees then
        return resolve_snapshot({
            bufnr = bufnr,
            winid = winid,
            row = row,
            col = col,
            parser = parser,
            trees = cached.trees,
            stale = true,
        }),
            nil
    end

    return nil, 'parse_pending'
end

M.snapshot_sync = M.snapshot

---@param snapshot { row: integer, col: integer, parser: vim.treesitter.LanguageTree, trees: table<integer, TSTree> }
---@return TSNode?
local function node_at_snapshot(snapshot)
    local range = cursor_range(snapshot.row, snapshot.col)

    if type(snapshot.parser.tree_for_range) == 'function' then
        local ok, tree = pcall(snapshot.parser.tree_for_range, snapshot.parser, range)

        if ok and tree then
            return collect.innermost_named_node_at(tree:root(), snapshot.row, snapshot.col)
        end
    end

    local tree = snapshot.trees[1]
    return tree and collect.innermost_named_node_at(tree:root(), snapshot.row, snapshot.col) or nil
end

---@param opts? { bufnr?: integer, winid?: integer, lang?: string, on_publish?: fun(bufnr: integer) }
---@return marginalia.ContextResult
function M.for_window(opts)
    local snapshot, reason = M.snapshot(opts)

    if not snapshot then
        return { frames = {}, reason = reason }
    end

    return {
        frames = collect.ancestors(
            node_at_snapshot(snapshot),
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
