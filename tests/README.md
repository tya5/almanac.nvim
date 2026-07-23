# Tests

Uses [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)'s busted-style framework. Unlike outlook.nvim, almanac.nvim has no external process/COM dependency, so these tests exercise real Neovim buffers/windows directly (headless), not mocks.

- `dateutil_spec.lua` — pure date-math (month/week/day ranges, grid building, English header formatting independent of system locale)
- `render_spec.lua` — month/week/day renderers: lines, highlights, and the line_map used for `<CR>` selection
- `init_spec.lua` — the `Calendar` class: window lifecycle (show/close/toggle), navigation, view/position switching, event emission (`:on(...)`), selection, async `EventProvider` support

## Running

```sh
nvim --headless --noplugin -u tests/minimal_init.lua \
  -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}"
```

`tests/minimal_init.lua` clones `plenary.nvim` into `stdpath("data")` on first run (not vendored in this repo).
