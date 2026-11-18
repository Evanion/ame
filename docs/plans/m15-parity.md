# M15: mockup parity pass

The in-game screens drifted from the "AME redesign" design canvas. A view-by-view comparison (Nov 2026) listed the
differences; this is the checklist.

**What the mockups decide, and what they don't.** The mockups are quick HTML sketches, not drawn with AME's in-game
components. They decide structure and content: what goes where, grouping (cards, rows, columns), alignment, which
elements exist, wording, ordering. They don't decide the components' look: AME's own colours and theme accents,
button / segment / checkbox / chip styles, borders, fonts and table striping stay as the widget library draws them.

Also kept on purpose (decided with the user after the mockups were made): gold in coin colours, abbreviated
quantities (4.5k), the "Sales/day" label, table counts under the table, the verdict card on the Item tab, item icons in
tables, + = - ~ $ signal glyphs.

## Shell
- [x] Sidebars start under the toolbar (no full-height left sidebar on Market and Guide)
- [x] Title bar: one market button ("PvP · Horde AH") instead of realm text + house dropdown; divider under the bar
- [x] Footer: busy text set apart from the version (capitalised: "Updating market data…")

## Item
- [x] Header subtitle: category, pips + scans this week, last seen; search box vertically centred
- [x] Chart: market as a line (no area), 7-day average dashed; horizontal grid only + axis rule; hint bottom-right
- [x] Legend: capitalised labels, "7-day average", swatch per kind (line, dashed line, square, dot)
- [x] Sidebar: verdict card opens with a "Verdict" label + signal (no huge glyph line), same average period as the
  cards; market card with the signal beside "Market price", change line in words ("56% above its 7-day average"), one
  confidence line; key numbers without 7d change, Supply and Sells per day split; post-at header "N ahead" dim, Normal
  row without pips, "you net … after the 5% cut", Quick / Patient values "price · time"; Watch shows the list name
- [x] Footer: "Prices from your full scan 2 h ago and N searches since"
- [x] Compact: short subtitle, no 1Y, summary bar in pieces (market + change, signal, post at + time)

## Sell bar
- [x] "AME" tag at the left, confidence on the right before the buttons (not in the title), "per unit" dim
- [x] Wording: "Just under N listed at X", "you net … after the 5% cut", "vendor pays …"; chance in the tooltip
- [x] Vendor case: one "Post anyway at …" button (no Quick / Patient), its own reason line

## Market
- [x] Toolbar spans the width with the signal filter on it; chips row only when there are chips, "Filters:" label
- [x] Sidebar: "Watchlists" and "Categories" headers, counts with separators
- [x] Columns: "vs 7-day avg"; drop order keeps "vs avg" longest; compact hides Supply and Score; Signal left-aligned
- [x] "Views ▾", "Columns · N hidden" wording; confidence pips right after the name

## Arbitrage
- [x] Summary line under the toolbar (count · both cuts · deposit basis)
- [x] "min profit g" / "min margin %" hints; "Data up to 3 days" wording
- [x] Columns: Units ("N of M") instead of Depth + Supply; "Buy", "Sell", "Data age"; Search on every row (disabled
  away from the buy house)
- [x] Sidebar as cards: name + "Goblin AH to Horde AH"; Buy at, Sells at, cut, Deposit if unsold, "You net"; data card
  with each side's source and age, "Sells per day there", an advice line; full-width "Search at the …" button

## Portfolio
- [x] Toolbar above the KPI cards; scope and period as segmented buttons
- [x] KPI labels "· 7 days"; auctions count as a sub line on card 2
- [x] Signal column left-aligned, with glyphs

## Settings
- [x] Three columns of framed cards: Window | Tooltips, Charts | Selling, Notifications, Data (+ Advanced cards)
- [x] Mockup wording; controls right-aligned in their rows; Data: one line and a row of three buttons (Import from
  Auctionator, Rebuild market data, Run self-test); minimap check under Data

## Sync
- [x] Freshness cards: the age as the value ("2 h old"), "Full scan by you · 6,782 items" under it; your house first
- [x] Three framed cards: Guild sharing (check, one stats line, guild members with AME), Trusted players (intro,
  name + "Ask to share", list, Requests), Blocked (intro, list, last rejected)
- [x] Status: "Sync is on · next announce in N min"

## Not taken from the mockups (component look)
Solid-filled selected segments, window / card / control colours, tab and close-button styling, chip and "Clear all"
link styling, table panel frames, header rules and row lines instead of stripes, signal pills, font sizes, the
sell bar's accent stripe, equal-height confidence pips.

## Done (Nov 2026), and where the game differs on purpose
All items above are in. Deliberate differences from the mockups:
- The chart keeps its in-game look (area under the market line, grid, colours); only the average is dashed.
- Signals use small tinted icons (up / down triangle, dot, pause, coin) before the word; the game fonts lack ▲▼●.
- Gold in coin colours, abbreviated quantities (4.5k), "Sales/day", the verdict card, item icons in tables.
- Market keeps subcategories in the sidebar and table counts under the table; Arbitrage keeps a Chart button and
  the Depth row in the route sidebar; the sell bar keeps "Normal" as a third choice and highlights the price in the
  box; Settings keeps the minimap check; Sync keeps all players heard from (guild and whisper) with Block.
- Sync shows no "next announce in" time (the announce timer isn't tracked for display).
- Not done: toolbars don't wrap (narrow windows
  switch to the compact layouts instead).
