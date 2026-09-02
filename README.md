# Marginalia

> [!WARNING]
> Marginalia's window-local conceal rendering uses private Neovim interfaces:
> scoped namespaces through experimental `nvim__ns_set()` where available, and
> the decoration provider's internal `_on_conceal_line` callback on Neovim
> 0.11. These interfaces may change across Neovim versions. If neither path is
> available, Marginalia disables conceal rendering rather than leaking conceal
> state into other windows.

Context-preserving Neovim editing experiments built around hiding irrelevant
lines instead of mirroring context into a floating overlay.

## Status

Early development. The current MVP selects Tree-sitter context frames, projects
visible rows plus conceal ranges, and materializes window-scoped Neovim
`conceal_lines` extmarks for attached windows. Neovim 0.12 uses scoped
namespaces; Neovim 0.11 uses a compatibility decoration provider that
materializes only the ranges requested for the window being drawn.

## Requirements

- Neovim 0.11 or newer
- installed Tree-sitter parsers for the filetypes where Marginalia is enabled

Linux is the primary supported and CI-tested platform. Stable Neovim is tested
through the Neovim 0.11 compatibility path; nightly is tested through scoped
namespaces when it exposes `nvim__ns_set()`. Marginalia currently publishes from
`main` without a stable release tag.

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

With `lazy.nvim`:

```lua
{
    'griwes/marginalia.nvim',
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

Run `:checkhealth marginalia` after installation. See `:help marginalia` for
the lifecycle and command overview.

`enabled` and `auto_attach` are lifecycle-level setup options. Context,
viewport, and render behavior belongs in the owning `context`, `viewport`, or
`render` table.

## Development

Run `scripts/ci/run.sh` for the repository-local Stylua, test, and clean-install
smoke checks. GitHub Actions runs them on Neovim 0.11.5, stable, and nightly,
validates workflow syntax with actionlint, and requires the experimental scoped
namespace API on nightly. Tests under `tests/` cover cursor-row stability and
screen-level window locality; the workflow is `.github/workflows/ci.yml`.

## License

Marginalia is Apache-2.0. The vendored context queries retain their upstream
MIT license and attribution; see [`queries/README.md`](queries/README.md).
