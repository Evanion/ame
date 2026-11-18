# M15: holistic redesign — spec and plan

Status: built (Nov 2026), P1-P8 committed with specs; in-game check and release pending (P9).

### As built (differences from the plan below)

- `UI.Slots` / `UI.Stack` in Core/UI/Shell.lua are the shared shell: each tab builds its slots in its content area;
  the window frame (title bar, resizing, docking, footer) stays in Window.lua.
- Compact mode: the right sidebar opens as a panel over the right of the main area (Details button), not under it.
- Arbitrage has no column chooser (its columns drop by priority when narrow); Market has one.
- Portfolio periods: Today, 7 days, 30 days, All time; "since weekly reset" left out (open question below).
- Click-a-listing re-targeting works on the game's sell window (the price that lands in its price box).
- Signals show a small tinted icon before the word (up / down triangle, dot, pause, coin): the game fonts lack ▲▼●.
- Colour-blind palette: Okabe-Ito blue (#56B4E9) / orange (#E69F00) for gains, losses, signals and candles.

Original status: agreed direction (Nov 2026). Mockups: the "AME redesign" design canvas. Research: competitive and user research
report (Nov 2026, kept out of the repo).

## Why

AME grew from a price recorder into a trading desk (screener, item charts, arbitrage, posting prices, portfolio,
sync) inside a fixed 980×500 window, so every screen is cramped and information-dense. Research findings that shape
the redesign:

- Neither Auctionator nor TSM draws price charts in game; several addons exist only to add one. The chart is AME's
  strongest differentiator: it gets the most space.
- Top pain points: slow / throttled scans (players blame the addon), complexity (TSM), stale or untrustworthy
  numbers, dated cramped UI. Top requests: price history, filters, account-wide ledgers, a scalable window, tooltip
  control.
- WoW Forever newcomers (Goblin Terminal, auxForever, ForeverSell) cover overlapping features. AME stands out on
  trustworthy numbers (every number says its period, age, source and confidence), faction ↔ goblin arbitrage, and
  posting prices that don't play the 1c undercut game.
- Position: the analysis desk that works alongside Auctionator, not a replacement AH.

## Principles

1. One shared shell; tabs only fill slots. Title bar, tabs, status row, resizing and breakpoints live in one place.
2. The main thing on each tab stretches (chart, table); everything else is fixed-size and secondary.
3. Every number is trustworthy at a glance: period, age, source, confidence — in the number's label, tooltip or the
   status row.
4. Signals are text + glyph + colour, never colour alone; a colour-blind palette is one setting away.
5. Progressive disclosure: few default columns, details on hover, Basic / Advanced settings; no tutorial tour.
6. Nothing overflows: text truncates with "…" (full text on hover), panels scroll, tables show as many rows as fit.

## Window

- Resizable from a bottom-right handle. Minimum 760×460, maximum the screen.
- Default size from the screen: width = clamp(60% of UIParent width, 900, 1100), height = clamp(75% of UIParent
  height, 520, 640). On a large screen 1100×640; on 1080p at default UI scale ~900×560.
- Two remembered placements (size + position, per character): with the auction house open, and without.
- Dock next to the AH (setting, on): when the AH opens and there's room to its right, AME anchors beside it;
  otherwise it keeps its "with AH" placement.
- Scale setting 70–120% (frame scale, independent of the game's UI scale).
- Breakpoint at 900 px width ("compact" below it):
  - left sidebars (Market categories) become a dropdown in the toolbar;
  - right sidebars (Item, Arbitrage) become a one-line summary with a "Details" panel under the main area;
  - tables hide their lowest-priority columns first (shown as hidden in the column chooser);
  - the title bar shows "AME" instead of the full name.

## Shared shell (code)

`UI.Shell` (Core/UI/Shell.lua) owns the window frame and builds, per tab, these slots:

| Slot | Size | Content |
|---|---|---|
| title bar | fixed 36 | logo, name, market picker, tabs, close |
| header | optional, fixed | item name + subtitle, or tab summary (KPIs) |
| toolbar | fixed, wraps when narrow | search, filters, ranges, modes |
| left sidebar | optional, fixed width, full height, scrolls | categories, watchlists |
| main | stretches both ways | chart or table |
| right sidebar | optional, fixed width, full height, scrolls | verdict, stats, details |
| status row | fixed 26 | data age / source text, "updating market data…", version, resize handle |

- A tab registers `{ key, label, header?, toolbar, left?, main, right?, status = fn }`; the shell lays the slots out
  on every size change and switches compact / full.
- New shared widgets: `W.ScrollPane` (wheel + thin scrollbar shown only when needed; used by sidebars, Settings,
  Sync, Guide), `W.Chips` (removable filter chips), `W.ColumnChooser`, `W.SignalBadge` (glyph + text + colour,
  confidence pips), `W.Collapsible` (compact Details panel).
- DataTable: row count follows its height (no fixed `rows`), relayout on size change (already column-flexible).
- Existing pieces carry over: W.Segmented, W.Input, W.Dropdown, W.StatCard, W.Tooltip, W.StatusLine, theme registry.

## Screens

### Item (main: chart; right sidebar 280)
- Header: icon, quality-coloured name, one-line subtitle (category · market · history · data confidence · last seen),
  search box right.
- Toolbar: ranges 2D 7D 30D 90D 1Y All; Line | Candles switch (two options, not a cycling button).
- Main: the chart fills everything below the toolbar. Legend as an overlay box in the top-left corner (one line per
  series, including your buys / sells), hidden while hovering the plot. Faint "Scroll to zoom · drag to pan ·
  double-click to reset" hint in the bottom corner.
- Right sidebar (scrolls), top to bottom:
  1. Verdict: market price (large), change vs the average period, signal badge with phase, confidence pips + scans.
  2. Key numbers list: lowest listing, average (period), volatility, supply (+ weekly trend), sells per day.
  3. Post at (listing length): Normal large with time to sell and your net after the cut; Quick and Patient lines;
     units ahead; hold / vendor warnings.
  4. Watch and alerts: watch menu button, below / above inputs, signal alert check.
- Compact: sidebar → summary line (market, change, signal, post-at) + Details panel.
- Status: "Prices from your full scan 2 h ago and 3 searches since".

### AH sell-window bar
- One recommendation: "Post at 11s 99c per unit", with a one-line reason: queue position ("just under 93 at 12s"),
  time to sell, your net after the cut, vendor price.
- Quick / Patient as secondary buttons; "Fill price" as the main button; confidence pips.
- Clicking a listing in the sell window re-targets the recommendation to just under it (game's sell frame; best
  effort for addon sell tabs).
- Vendor case: "Vendor it: a vendor pays more" with the numbers, and "Post anyway at …".

### Market (main: table; left sidebar 190)
- Toolbar: search, quality, min / max gold, signal segments (All, Buy, Hold, Sell, Wait, Vendor) with glyphs,
  Views (saved filter sets), Columns (chooser, "N hidden").
- Chips row for active filters with "Clear all".
- Left sidebar: All items, watchlists (+ New list), categories with counts; scrolls; compact → dropdown.
- Default columns: Item (with confidence pips), Market, vs average, Supply, Sells/day, Signal, Score. Optional:
  Lowest, Volatility, 7d change, Data age, Phase.
- Stale rows (data older than 3 days) fade; signal hover explains its reasons.
- Status: count, rows shown, index age.

### Arbitrage (main: table; right sidebar 260)
- Toolbar: Buy at ⇄ Sell at, min profit, min margin, data age, Columns.
- Summary line: routes, both cuts, deposit basis.
- Table: Item, Buy, Sell, Net (after cut and deposit), Margin, Units (profitable / listed), Sells/day, Data age,
  Search.
- Right sidebar for the selected route: price → cut → deposit → net breakdown; age and source of each side; sell
  rate; warning when a side is old; main button "Search at <house>".

### Portfolio (main: table)
- Toolbar: modes (Positions, Ledger, Auctions, Customers, Suppliers); Account | This character; period (Today,
  7 days, 30 days, All — "since weekly reset" if the reset time can be derived); Export (copyable text box: WoW
  can't write files).
- Header: KPI row (holdings, listed now, unrealized, realized in period, sold / bought in period).
- Table per mode; Ledger profit shown by default.

### Settings (main: scrolling columns)
- Basic | Advanced. Basic sections: Window (scale, dock, open / close with AH, switch to Item when selling, colours,
  colour-blind palette), Tooltips, Charts, Selling, Notifications, Data actions.
- Advanced adds: data quality (outlier filter), retention, sync tuning, diagnostics.

### Sync (main: scrolling columns)
- Header: freshness per auction house (age, who scanned, items).
- Columns: Guild sharing (+ members heard), Trusted players (+ requests), Blocked (+ last rejection).

### Guide
- Wider, scrolling glossary of every metric and signal (period, formula, thresholds); column and card tooltips link
  to their entry.

### Tooltips
- Default three lines: market (average period) with change, supply · sells/day, signal. Shift adds: lowest, volatility,
  score, confidence, data age. Never repeat Auctionator's own lines where both are shown.

### First run and empty states
- No tour. Empty tabs say what to do next ("Open the auction house and run a full scan").
- Scans show a real progress count in the status row.
- One-time hints on first use of a feature (posting bar, arbitrage).

## Plan

Each phase is its own set of commits with specs green; no release until the user says so.

| Phase | Delivers | Tests |
|---|---|---|
| P1 Shell and window | Shell.lua with slots; resizable window, min / max, default from screen, two placements, dock next to AH, scale; breakpoint switching; W.ScrollPane; DataTable rows follow height; every tab moved onto the shell with today's content | integration specs at 1100×640 and 760×460 (stub sizes); placement and docking specs |
| P2 Item | header, toolbar, chart fill, legend overlay, right sidebar (verdict, numbers, post at, watch), compact summary + Details | item specs at both sizes; legend toggles on hover |
| P3 Sell bar | one recommendation + reason + net + vendor, Quick / Patient / Fill, vendor variant, click-a-listing re-target | SellAssist specs incl. re-target and vendor case |
| P4 Market | filter chips, signal segments with glyphs, column chooser (persisted), saved views, confidence in the Item column, stale fading, signal reasons tooltip, compact category dropdown | screener specs for chips, views, columns, staleness |
| P5 Arbitrage | route sidebar with net breakdown, per-side age and source, summary line | arbitrage view specs |
| P6 Portfolio | account / character switch, periods, export box, KPI header | portfolio specs per period / scope |
| P7 Settings and Sync | Basic / Advanced, Window section, colour-blind palette (signals, chart), Sync freshness header | settings / sync specs |
| P8 Guidance | empty states, scan progress, one-time hints, tooltip 3 lines + Shift, Guide glossary links | tooltip and empty-state specs |
| P9 Polish and release | translations for new texts, in-game check at both sizes (1080p and ultrawide), changelog | locale spec; in-game checklist |

Order follows impact from the research (sell bar and Item first after the shell); P1 is the foundation everything
else needs.

## Out of scope (for now)

- Gamepad support, a desktop / web companion, a sniper or auto-buy (not allowed: every buy, post and cancel needs the
  player's click), replacing Auctionator's buying / selling flows.

## Open questions

- "Since reset" in Portfolio needs the weekly reset time per region on Forever: derive it, or skip it.
- Click-a-listing re-targeting in addon sell tabs (Auctionator): hookable or game sell frame only.
- Colour-blind palette: Okabe-Ito (blue / orange) as the alternative signal and chart colours — confirm in game.
