# Marginalia

> [!WARNING]
> Marginalia currently depends on Neovim's experimental `nvim__ns_set()` API
> to scope `conceal_lines` extmarks to one window. The API may change or
> disappear across Neovim versions. When it is unavailable, Marginalia safely
> disables conceal rendering rather than leaking conceal state into other
> windows.

Context-preserving Neovim editing experiments built around hiding irrelevant
lines instead of mirroring context into a floating overlay.

## Status

Early development. The current MVP selects Tree-sitter context frames, projects
visible rows plus conceal ranges, and directly materializes window-scoped
Neovim `conceal_lines` extmarks for attached windows.

## Current API

- `require('marginalia').setup(opts)` normalizes plugin configuration.
- `require('marginalia').enable()`, `disable()`, `toggle()`, and `refresh()` manage the current window.
- `require('marginalia').debug_snapshot()` returns context, viewport, render, and transaction state for inspection.
- `:MarginaliaEnable`, `:MarginaliaDisable`, `:MarginaliaToggle`, `:MarginaliaRefresh`, and `:MarginaliaDebug` manage or inspect the current window.

The default integration uses a context-focus scope above the cursor. It keeps
ancestor rows, the cursor row, and rows required by `scrolloff`, then conceals
the planned non-context rows between them.

Cursor movement is part of the rendering contract. Adjacent linewise movement
keeps the traversed rows visible so that moving one buffer line down advances
the cursor by one physical screen row, even when the conceal plan is recomputed.

## Provenance

Marginalia is Apache-2.0. Initial code is original and scaffolded from the
workspace Apache-2.0 plugin template.

The `queries/` directory vendors Tree-sitter context queries from
`nvim-treesitter/nvim-treesitter-context` at
`b311b30818951d01f7b4bf650521b868b3fece16`. Those query files are licensed
under the upstream MIT license; the license text and attribution are reproduced
in `queries/LICENSE.nvim-treesitter-context` and `queries/README.md`.

## Installation

Example local `lazy.nvim` spec:

```lua
{
    dir = vim.fn.expand("~/projects/neovim-plugin-orchestration/marginalia.nvim"),
    name = 'marginalia.nvim',
    opts = {
        context = {
            max_depth = 4,
            skip_node_types = {
                'chunk',
                'program',
                'source_file',
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
    },
}
```

`enabled` and `auto_attach` are lifecycle-level setup options. Context,
viewport, and render behavior belongs in the owning `context`, `viewport`, or
`render` table.

## Development

- tests live in `tests/`
- cursor-row stability is covered by unit tests; protocol/PTY probes are external Ralph verification artifacts unless explicitly adopted later
- formatting is enforced with Stylua
- Lua modules should carry LuaLS annotations and doc comments
- CI lives in `.github/workflows/ci.yml`
