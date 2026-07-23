# almanac.nvim

A generic, data-source-agnostic calendar/agenda UI for Neovim: month, week, and day views in a reusable sidebar window, styled after [snacks.nvim](https://github.com/folke/snacks.nvim)'s public-API conventions (`Snacks.win`/`Snacks.picker`). almanac.nvim itself knows nothing about *where* events come from — you hand it an `EventProvider` and it renders whatever it's given.

Its first consumer is [outlook.nvim](https://github.com/tya5/outlook.nvim) (an Outlook COM bridge), but almanac.nvim has no dependency on it or on any specific data source — Google Calendar, org-mode, a local `.ics` file, anything that can produce a list of `{id, title, start, ...}` events works.

> **Status:** v1 implemented (month/week/day views, sidebar window management, position/view cycling, edgy.nvim-aware). Not yet published/tagged for wider use. See [docs/DESIGN.md](docs/DESIGN.md) for the full API/IF spec and design rationale.

## Features

- **Three views** — month (traditional grid), week (7-day agenda), day (hourly time-axis) — sharing one `Event` data model and `EventProvider` contract. Switch with `gm`/`gw`/`gd` or cycle with `<Tab>`.
- **Sidebar window**, nvim-tree/neo-tree style: left/right/top/bottom/float, reused across opens (not a floating popup, not a takeover of your current window). Cycle position with `<C-w><C-w>`.
- **Any data source**: `events` can be a static `Event[]` table or an async `function(range, cb)` — mirrors `snacks.picker`'s finder contract (called once per visible-range change).
- **[edgy.nvim](https://github.com/folke/edgy.nvim) aware**: if present (e.g. via LazyVim's `:LazyExtras` → `ui.edgy`), almanac's own position-cycling steps aside and lets edgy coordinate the sidebar alongside your other edgebars (neo-tree, Trouble, etc.) — see below for the copy-paste stanza.
- **English-only UI text**, for global use; only your own event data (titles, locations) passes through untranslated.
- All highlight groups are linked (`default = true`), never hardcoded, so any colorscheme applies automatically.

## Requirements

- Neovim >= 0.10

## Installation

```lua
-- lua/plugins/almanac.lua
return {
  "tya5/almanac.nvim",
}
```

almanac.nvim is a library, not a standalone command-driven plugin — you construct and drive a `Calendar` instance yourself (see Usage), typically from another plugin or a small wrapper in your own config.

## Usage

```lua
local Almanac = require("almanac")

local cal = Almanac({
  events = {
    { id = "1", title = "Team sync", start = os.time() + 3600 },
  },
})

cal:show()
```

Async data source (called once per visible range; see [docs/DESIGN.md](docs/DESIGN.md) 3.2):

```lua
local cal = Almanac({
  events = function(range, cb)
    my_backend.fetch(range.from, range.to, function(events)
      cb(events)
    end)
  end,
})
```

React to selection:

```lua
cal:on("event_selected", function(_, event)
  print("selected: " .. event.title)
end)
cal:on("day_selected", function(_, epoch)
  print(os.date("%Y-%m-%d", epoch))
end)
```

## API

See [docs/DESIGN.md](docs/DESIGN.md) section 3 for the full spec. Summary:

```lua
cal:show() / cal:close() / cal:toggle()
cal:next() cal:prev()               -- page by the *current view's* unit: month/week/day (default <C-f>/<C-b>)
cal:next_day()  cal:prev_day()      -- move the focused day (cursor), regardless of view
cal:next_week() cal:prev_week()
cal:next_month() cal:prev_month()   -- jumps to day 1 of the target month
cal:goto_date(epoch) cal:today() cal:refresh()
cal:set_view("month"|"week"|"day")  cal:cycle_view()
cal:set_position("left"|"right"|"top"|"bottom"|"float")  cal:cycle_position()
cal:selected_day()  cal:selected_events()
cal:on(event, callback)   -- range_changed, view_changed, day_selected, event_selected, position_changed, close
cal:map(lhs, action)      -- same shapes as opts.keys
```

## Configuration

```lua
require("almanac")({
  date = os.time(),        -- initial focused day; default: today
  view = "month",           -- "month" | "week" | "day"
  week_start = "monday",     -- "sunday" | "monday"
  position = "left",         -- "left" | "right" | "top" | "bottom" | "float"
  size = 30,                 -- columns (left/right) or rows (top/bottom); <=1 is a fraction
  manage_position = "auto",  -- "auto": defer to edgy.nvim if present | "always": always self-manage
  events = nil,              -- Event[] or function(range, cb) — see docs/DESIGN.md 3.2
  keys = { --[[ see docs/DESIGN.md 3.4 for the full default table ]] },
  wo = {}, bo = {},          -- window-/buffer-local options
  on_open = nil, on_close = nil,
})
```

`require("almanac").setup(opts)` optionally changes the *global* defaults picked up by every subsequent `Almanac(opts)` call — not required, each call can pass its own opts instead.

### Keymaps (sidebar buffer, `filetype = "almanac"`)

| Key | Action |
|---|---|
| `h`/`l` | move focused day: previous/next day |
| `j`/`k` | move focused day: next/previous week |
| `<C-f>`/`<C-b>` | page by the current view's unit (month in month view, week in week view, day in day view) |
| `gt` | today |
| `gm`/`gw`/`gd` | switch to month/week/day view |
| `<Tab>` | cycle view (month → week → day) |
| `<CR>` | select day/event under cursor (`day_selected`/`event_selected`) |
| `<C-w><C-w>` | cycle sidebar position (no-op if edgy.nvim is managing it) |
| `q` | close |

## edgy.nvim integration

If you use [edgy.nvim](https://github.com/folke/edgy.nvim) (bundled as a LazyVim extra: `:LazyExtras` → `ui.edgy`), add a stanza like this so almanac's sidebar is coordinated alongside your other edgebars:

```lua
-- in your edgy.nvim opts
{
  "folke/edgy.nvim",
  opts = {
    left = {
      { ft = "almanac", title = "Calendar", size = { width = 30 }, pinned = true },
    },
  },
}
```

With edgy.nvim present, almanac's own `cycle_position()` becomes a no-op by default (`opts.manage_position = "auto"`) so the two don't fight over the same window — position management is edgy's job. Set `manage_position = "always"` to keep using almanac's own cycling regardless.

## Health check

```vim
:checkhealth almanac
```

## Design documentation

- [docs/DESIGN.md](docs/DESIGN.md) — full API/IF spec, data model, rendering approach, ecosystem integration research (edgy.nvim, prior art), roadmap
- [tests/README.md](tests/README.md) — how to run the test suite

## Contributing

Lua formatting uses [StyLua](https://github.com/JohnnyMorganz/StyLua) (`stylua.toml`); run `stylua .` before committing. See [tests/README.md](tests/README.md) for running tests.

## License

[MIT](LICENSE)
