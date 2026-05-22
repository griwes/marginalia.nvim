# Marginalia

Context-preserving Neovim editing experiments built around hiding irrelevant
lines instead of mirroring context into a floating overlay.

## Status

Early development. The current MVP selects Tree-sitter context frames, plans
protected/hidden rows, and applies Neovim `conceal_lines` extmarks in attached
windows.

## Current API

- `require('marginalia').setup(opts)` normalizes plugin configuration.
- `require('marginalia').get_context(opts)` returns current tree-sitter context frames when a parser is available.
- `require('marginalia').plan_hidden_ranges(opts)` computes protected and hidden rows without changing the editor.
- `require('marginalia').enable()`, `disable()`, `toggle()`, and `refresh()` manage the current window.
- `:MarginaliaEnable`, `:MarginaliaDisable`, `:MarginaliaToggle`, and `:MarginaliaRefresh` manage the current window.

The default integration uses a context-focus scope above the cursor. It keeps
ancestor rows, the cursor row, and rows protected by `scrolloff`, then conceals
the planned non-context rows between them.

Cursor movement is part of the rendering contract. Adjacent linewise movement
keeps the traversed rows visible so that moving one buffer line down advances
the cursor by one physical screen row, even when the conceal plan is recomputed.

## Provenance

Marginalia is Apache-2.0. Initial code is original and scaffolded from the
workspace Apache-2.0 plugin template. Do not copy or adapt code from
non-Apache-2.0-compatible projects. If compatible external code is ever copied
or adapted, reproduce that source's license and provenance in this repository.

## Installation

Example local `lazy.nvim` spec:

```lua
{
    dir = vim.fn.expand("~/projects/neovim-plugin-orchestration/marginalia.nvim"),
    name = 'marginalia.nvim',
    opts = {},
}
```

## Development

- tests live in `tests/`
- cursor-row stability is covered by unit tests; protocol/PTY probes are external Ralph verification artifacts unless explicitly adopted later
- formatting is enforced with Stylua
- Lua modules should carry LuaLS annotations and doc comments
- CI lives in `.github/workflows/ci.yml`
