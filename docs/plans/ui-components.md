# UI components: the Lua UI built from the canvas's components

Status: plan (Nov 2026). Nothing here is built yet. The design canvas ("AME redesign", the Design artifact) was
reorganised so every artboard is built from shared components that mirror widgets in the addon. This plan does the
same for the Lua UI. Each canvas component gets one Lua widget, the views are rebuilt from them one at a time, and
the views end up matching their artboards.

Line numbers are as of 1e73082 with [data-core](data-core.md) step 1 (formatting helpers) in the working tree, so
they may be off by a few lines in the files that step touches (`AHSelling`, `AHShopping`, `ArbitrageView`,
`ItemView`, `LevelingView`, `ProfessionBar`, `SellAssist`, `Tooltip`, `Widgets`).

Agreed order: data-core steps 1–7 (behaviour-preserving) first, then this plan, then data-core steps 8–11. See
[Coordination with data-core](#coordination-with-data-core) for the files both plans touch.

## Rules the work follows

- **Every item name is an item link**: quality colour, icon, the item's tooltip on hover, and Shift-click (or
  another modified click) does what it does on a link in chat. That means a DataTable item column, the new
  `W.ItemLink`, or an inline link in a text that has links switched on. Tooltips can't be clicked, but item names in
  them are still quality-coloured.
- **No "AME" prefixes** in tooltips, AH tabs or labels. The window's own title stays.
- **One look**: grey borders (`W.Skin` with `W.COLORS`), DataTable for every list, Sidebar for every side menu, Card
  for every label / value panel.
- **Fill**: sidebars and content take the space they have. Lists grow rows as the window grows, not fixed counts.
- **Presentation only.** This plan changes how things are drawn and which widget draws them, not what is computed.
  Features that exist only in Lua stay. Features that exist only in an artboard are listed in
  [Artboard features not built yet](#artboard-features-not-built-yet) for the user to pick from; they are not slipped
  into a componentization commit.

## Findings that cut across every view

1. **DataTable item rows aren't item links.** The row's `OnClick` (`Core/UI/DataTable.lua:192-206`) calls
   `opts.onClick` or `UI:ShowItem` and never `W.ItemLinkClicked`, so Shift-click links nothing in any table. The
   Market screener uses Shift-click to search the AH (`Core/UI/MarketView.lua:814-820`).
2. **`W.Primary` has no look of its own.** It sets `b.primary` and calls `SetSelected(true)`
   (`Core/UI/Widgets.lua:217-221`), and nothing reads `b.primary`. The design has two looks: primary is a solid accent
   fill with white text, selected is a dark tint with an accent border. Several views call `SetSelected(true)`
   directly instead (`SellAssist.lua:235`, `ArbitrageView.lua:269`), and CraftingView and LevelingView never mark a
   main action.
3. **There is no Sidebar widget.** `UI.Sidebar` (`Core/UI/Shell.lua:25-35`) is only a panel with a scroll pane. The
   list of lines (heading, line, selection, count) is written five times:
   - `MarketView.lua:326-435`
   - `AHShopping.lua:303-329` and `:707-727`
   - `SettingsView.lua:63-83`
   - `Help.lua:946-981`
   - `CraftingView.lua:813-846`

   `Window.lua:564-566` also reaches into `mv.side.lines` to repaint them when the theme changes.
4. **Label / value cards are hand-built.** `UI.Stack:Pair` (`Shell.lua:158-173`) has a label and a right-aligned
   text value, with no money typing, signed, total (rule and bold), big or note. So views hand-roll rules
   (`ArbitrageView.lua:247-250`), font swaps (`ItemView.lua:294-298`, `ArbitrageView.lua:252-253`) and sign colours
   (`ArbitrageView.lua:353-357`). `CraftingView`'s `setLines` (`:1236-1243`) packs pre-formatted money into Pair
   values on every page.
5. **KPI tiles are `W.StatCard`**: a label and one small value, 42 px (`Widgets.lua:475-525`). Deltas, the "/day"
   and the breadth are glued into the value text (`MarketOverview.lua:507-549`, `PortfolioView.lua:263-264`,
   `:483-488`). The design's KpiCard has a separate delta tone, a rise / fall bar, a note, a second amount and a
   compact form.
6. **Signals have one look.** `W.SignalGlyph` is an icon and the word in its tone, which is the design's
   *plain* SignalBadge. Nothing draws the badge itself (the tinted pill) that the design's DataTable signal columns,
   the item card and the profession bar use. `format = "signal"` in DataTable (`DataTable.lua:56-58`) is the word
   only, with no icon.
7. **Item names drawn as text.** The list is in each view below. The common causes:
   - `W.ItemLabel` / `W.QualityText` / `ItemCache.Name` written into a string with no hover.
   - A DataTable with only one item per row (`opts.itemID`): a second item in a row (Refine's "Craft X", Leveling's
     recipe item) can't be one.
   - `UI.ItemLine` in CraftingView: a hover frame with no icon.
8. **Hard-coded tones** outside `W.COLORS` / `ns.HEX`. The main ones:
   - Chart and legend colours: `ItemView.lua:166`, `:219`, `:637-659`, `:690`, `:728-733`; `MarketOverview.lua:655`.
   - Material Tags: `ProfessionBar.lua:665-666`.
   - Leveling's colour bar: `LevelingView.lua:396`, `:403`.
   - The Launcher's greys: `Launcher.lua:88`, `:152-160`.
   - The notice badge: `Notices.lua:43`, `:129`.
   - The `|cff33ccffAME|r` chat prefixes: `ProfessionBar.lua:237`, `:338`, `:353`; `ShoppingView.lua:217`, `:281`,
     `:324`. `ns.AME.Say` exists for these.
9. **"AME" in visible text**:
   - `Tooltip.lua:164` ("Hold Shift for more AME data")
   - `SettingsView.lua:210` ("Show AME prices in item tooltips")
   - `AHShopping.lua:702` ("make one in the AME window…")
   - `SellAssist.lua:483` ("AME suggests…")
   - `ScanButton.lua:242` ("AME records it…")
   - `Launcher.lua:138` ("AME notifications")
   - The SellBar tag (`SellAssist.lua:250`) and the Guide's copy of it (`Help.lua:826`) are in the artboard too.
     Whether they stay is a question for the user.
10. **Integration specs reach into view internals**:
    - `itemView.cards`, `.legend`, `.legendBox`, `.postNet`, `.postHead`, `.sub`, `.watch`
    - `marketView.table`, `.headers`, `.side.lines`, `.counts`, `.search`, `.rows`
    - `settingsView.sections`, `.current`
    - `overviewView.largestRows`, `noticePanel.rows`, `views.guide.term`

    `tooltip_spec` asserts on `Tooltip.Lines` text. A view step keeps these handles (as aliases where the widget
    renames them) or updates the spec in the same commit and says why. A step that changes an expected value is
    wrong: this plan changes drawing, not numbers.

## (a) Component map

Each canvas component (`componentsNote` in `canvas.json`), its Lua counterpart today, and what's missing. "New" is a
widget this plan adds. All of them go in `Core/UI/Widgets.lua`, except where `Shell.lua` is named.

| Canvas | Lua today | Missing / to do |
|---|---|---|
| **ItemLink** (star, icon, quality colour, count, confidence, size, bold) | In tables: the DataTable item column (`DataTable.lua:511-519`). Elsewhere: `W.QualityText` + `W.ItemHover` (`Widgets.lua:734-758`) wired by hand in 4 files, and `UI.ItemLine` in CraftingView. | **New `W.ItemLink(parent, opts)`**: icon, name, count, optional confidence and star, one hover / click frame (`ItemHover`). `:SetItem(key, count)`, `:SetFont(size, bold)`, `:GetWidth()` for flowing. **New inline form** `W.LinkText(key, count)` for item names inside sentences, with `W.EnableLinks(frame)` switching on `SetHyperlinksEnabled` plus `OnHyperlinkEnter/Leave/Click` (precedent: `Help.lua:1077-1086`). The DataTable item column gets modified-click linking (finding 1). |
| **DataTable** (types item, money, signedMoney, count, pct, signal, tag, button, share, text; rows selected / faded; `bare`; `note`) | `ns.DataTable` has item, `format` money / pct / plainpct / rate / count / signal, `text` functions, one `action` button, `selected`, `rowAlpha`, `fill`, `status`. | Modified-click item linking. `bare` (no header row). `note` (a dim line under the rows, wrapped, inside the table's frame). `format = "signedMoney"`. `share` cells (a 64 px track and bar, full at `col.max` (0.4 by default), the % beside it). `signal` cells drawn as a SignalBadge. `tag` cells (Tag). **Per-column item keys** (`col.item = function(d) return key end`), so a row can have more than one link. A `button` column with per-row label and variant (Craft queue's Buy / ✕). The stripe and selected colours stay DataTable's; nothing else copies them (`AHShopping.lua:501`). |
| **Sidebar** (entries heading, or label / count / note / selected / kind link, dim or done) | None (finding 3). | **New `UI.SideList(sidebar, opts)`** in `Shell.lua`. `:SetEntries({ {heading=…} \| {label, count, note, selected, kind, indent, key} })`, `opts.onClick(entry, button)`. Lines grow with the height, as `MarketView.lua:345-354` does now, and scroll with the wheel. The selected line's text turns white. `kind` sets the colour: link #8bb8ff, dim, done in good. `indent` covers subclasses and guild lists. Keeps `.lines` for `Window.lua:564` and the integration spec, then the theme repaint moves inside the widget. |
| **Card** (title or item, subtitle, rows `{label, copper\|text, signed, color, total, big}`, note) | `UI.Stack:Card` (`Shell.lua:134-143`) plus `:Pair` / `:Text` / `:Heading`. | **New `card:SetContent{ title, titleColor, item, count, subtitle, rows, note }`** on `UI.Stack:Card`, with a pool of rows: money typed (`W.Money`, `W.SignedMoney` with `full`), `total` (rule above and bold), `big` (large font), `color`, `term` (Help hover), and an optional `item` on the label (an inline link). `Pair` stays for one-off rows. Each row keeps `.label` / `.value` font strings, so `itemView.cards[n].value.text` still works. |
| **KpiCard** (label, value or copper / copper2, signed, delta + deltaKind, rise / fall bar, note, compact) | `W.StatCard` / `W.CardRow`. | **New `W.KpiCard(parent, opts)`**: `:Set{ value \| copper, copper2, signed, delta, deltaKind = "up"\|"down"\|"mute", rise, fall, note }`, `:SetCompact(on)`. `W.CardRow` builds KpiCards (it keeps its name and `row.cards`). `W.StatCard` goes once nothing uses it. |
| **SettingsCard** (title; rows check / indented check, field + dropdown, text, input + button, person) | A local `card()` / `check()` / `dropdown()` / `paragraph()` in `SettingsView.lua:129-157`. SyncView rebuilds cards by hand (`SyncView.lua:123`, `:194`, `:240`) and puts the protocol dropdown right after its label instead of right-aligned (`:143-160`). | **New `UI.SettingsCard(stack, title, rows)`** in `Shell.lua`, lifting SettingsView's helpers. Row kinds: `{check, key, indent}`, `{field, control}`, `{text}`, `{input, button}`, `{list = W.RowList opts}` (person rows), `{buttons}`. Settings and Sync both use it. The multi-column flow (`SettingsView.lua:30-32`, `:115`) stays (it's the fill rule). |
| **Button** (normal, primary, selected, disabled; `color` for the label) | `W.Button`, `W.Primary` (no look, finding 2). | `W.Primary` gets its own look: a solid accent fill with a white label and a slightly lighter hover. The fill is the accent at a shade that keeps white at 4.5:1 or better on all three themes, because full-strength Horde red is about 3.9:1 (see the comment at `Widgets.lua:77-79`). It's re-tinted by `W.SetTheme` like selected buttons. `opts.color` gives a label colour. Every main action calls `W.Primary`; the direct `SetSelected(true)` stand-ins go. |
| **Segmented** | `W.Segmented` | Matches. The Make / Buy pair in the craft queue becomes one (`ProfessionBar.lua:697-700`, `:825-826`). |
| **Input** | `W.Input`, `W.MoneyInput` | Matches. |
| **Check** | `W.Check`, `W.SettingCheck` | Matches. The minimap check built by hand (`SettingsView.lua:191-195`) uses the SettingsCard row. |
| **SignalBadge** (`plain`: words in tone) | `W.SignalGlyph` = plain. | **New `W.SignalBadge(parent)`**: a small frame with a tinted pill and the word, `:SetSignal(s)`. A DataTable `signal` cell draws one. **`W.SignalText(s)`** names the plain form (an alias of `W.SignalGlyph`, which is kept). |
| **SignalButton / SignalFilter** | `W.Segmented` with `{key, W.SignalGlyph(key), W.SignalTone(key)}` (`MarketView.lua:743-755`). The compact copy has no tone (`:838-849`). | **New `W.SignalFilter(parent, opts)`**: `signals`, `short` (icons only), `onSelect`, built on `W.Segmented` with `W.SignalTone`, so wide and compact share it. Its selected look is a question for the user (below). |
| **GameTooltip + TooltipBlock** | A pure `Tooltip.Lines(s, opts)` (rows `{left, right, middle}`, `Tooltip.lua:77-248`) and `Tooltip.AddRows` (`:503-571`). Recipe rows, recipe sources and "Made by" are added outside it (`:451-477`). | **Extend `Tooltip.Lines` into the block model**: a header, the grid (column heads), have, context, notice, signal, then `sections = { {heading, note, rows \| lines} }`. Rows gain bits for item names (quality-coloured), the warn icon and confidence. A row stays `{left, right, middle}` so `tooltip_spec` keeps passing. **`W.TipSection(tip, heading, note)`** draws the small-caps grey heading once. Launcher, ShoppingView's "Held by" and Portfolio's tooltips render through `Tooltip.AddRows`. |
| **Money** (size, bold) | `W.Money`, `W.SignedMoney`, `W.BigMoney` | Matches. Size and bold are the font string's (`W.Text` font objects); Card `big` and KpiCard pick them. |
| **Tag** (other, ah, made, vendor) | `TAG_COLORS` frames in `ProfessionBar.lua:664-678`, `:875-889` (only `ah` coloured; `made` falls back to `panelHover`; `carried` is dead, `:539-541`). | **New `W.Tag(parent)`**: `:Set(text, kind)`, colours in `W.COLORS.tag*`, accent-tinted `made` (follows the theme). Also a DataTable `tag` cell. |
| **CraftingToolbar** (search over the sidebar, scope buttons, checks, actions on the right) | One `LayoutToolbar` (`CraftingView.lua:847-945`), with Leveling injecting controls through `v.modes` (`:853`, `LevelingView.lua:345`). | **New `UI.CraftingToolbar(v)`** in `CraftingView.lua` (only Crafting uses it): `search` (sidebar width), `scope` (character, profession), `checks` slot, `actions` slot (right). A page declares `{ search = bool, scope = bool, checks = {...}, actions = {...}, extra = fn }`. Leveling's goal Segmented and profession / target pickers go in `extra` instead of `v.modes`. |
| **CraftingNav** | Hand-built (`CraftingView.lua:813-846`). | `UI.SideList` with the page entries and counts (professions, queue steps, recipes to buy). |
| **TitleBar** | `Window.lua:176-214`: tabs, a house dropdown, a gear for Settings, the notifications bell. | The active tab gets the design's look (accent fill, white label; the `W.Primary` look). The gear and bell stay (Lua-only features). Settings as a text tab is a question for the user. |
| **StatusBar** | `Window.lua:223-273` | The busy text ("Updating market data…") goes on the right before the version, in `warn`, not prepended on the left (`:271-273`). |
| *(panel)* | `AHShopping`'s `T.Panel` (`AHShopping.lua:170-178`), reused by Selling; `panel()` / `heading()` in `MarketOverview.lua:121-138` | **`W.Panel(parent)`** (`W.Skin` with `panel`). The copies go. |
| *(page heading)* | None | **`W.PageHeading(parent)`**: a gold title and a dim subtitle on one baseline (Crafting pages, the vendor panel, the AH tabs' list titles). |

## (b) Per view: how it differs from its artboard

Each list is what the view's step changes: layout, controls, colours, item names, and hand-rolled pieces that become
widgets. "Lua only" items stay.

### Window shell (`Window.lua`, `Shell.lua`) — Shell, TitleBar, StatusBar

- The slots match the Shell artboard (`Shell.lua:200-304`). The artboard has the compact right sidebar as a panel
  under main; Lua uses a Details overlay (`Shell.lua:10-12`, `:273-276`). Keep the overlay: it's what the compact
  artboards show too (ItemCompact).
- The active tab is drawn as a Segmented selected button; the design fills it with the accent (TitleBar, `.tb.on`).
- Busy text placement (StatusBar row above).
- Sidebar widths: `UI.SIDEBAR_W` 200 and `UI.SIDE_PANEL_W` 280 stay. The 190 / 260 / 270 in individual artboards
  are drawing slack. Shell.dc.html says 200 / 280, and AHShopping's own `T.SIDE_W` (`AHShopping.lua:18`) switches to
  `UI.SIDEBAR_W`.

### Market screener (`MarketView.lua`, `Watchlists.lua`) — Market, MarketCompact, Menus

- **Sidebar**:
  - Hand-built lines (`:326-435`) become `UI.SideList`.
  - "+ New list" / "+ New shopping list" (`:187`, `:222`) become `kind = "link"`.
  - The guild owner (`:201`, `:226`) becomes `note`.
  - Indents by leading spaces (`:201`, `:226`, `:240`) become `indent`.
  - The selected line's text turns white (`:414-416`).
  - Guild shopping lists get their count (`:228`).
- **Signal filter**: `W.SignalFilter` replaces the two Segmented copies (`:743-755`, `:838-849`).
- **Signal column**: `W.SignalGlyph` text (`:71-73`) becomes a SignalBadge cell.
- **Note**: the table gets the artboard's note ("Faded rows…").
- **Shift-click**: finding 1. The screener's Shift-click-to-search (`:814-820`) and item linking need one rule
  (question below).
- **Chips** (`W.Chips`, `Widgets.lua:405-441`): the design's pills ("✕", a link-blue "Clear all") are a small
  restyle inside `W.Chips`. The "Filters:" label (`:756-757`) stays (Lua only).
- **Menus** (`Watchlists.lua:52-137`):
  - The header is disabled `W.QualityText` text (`:57`); it should be an item name with the item tooltip.
  - `W.Menu` (`Widgets.lua:1295`) has no separators and no ▸ for submenus.
  - Both get `{ separator = true }` and `{ submenu = true }` entries.
- **Lua only**: the Hidden and Guild watchlists sections, optional columns, the counts under the table
  (`DataTable status`, `:821`). The artboard has the counts in the status bar.

### Market Overview (`MarketOverview.lua`) — MarketOverview, MarketOverviewCompact

- **KPI tiles**:
  - `W.CardRow` of `W.StatCard` (`:251-261`) becomes KpiCards. The delta (`:507-509`), "/day" (`:544`) and
    breadth bar (`:546-549`) move to their own fields.
  - Label "Market index" stays: the artboard's "AME price index" breaks the no-AME rule.
  - Lua's CPI tile stays.
- **Lists**:
  - `rowList` (`:142-191`) is a font-string table behind four lists. Risers, fallers and largest become `bare`
    DataTables, which gives them icons, links and fill.
  - Categories becomes a DataTable with a `share` column, replacing the hand texture (`:594`) and its separate %
    cell (`:593`).
  - The hand-built header (`:310-315`) goes. The "Change" header becomes "7 days" as in the artboard, only if the
    column really is the 7-day change; check this.
- **Item names**: movers (`:564`) and largest (`:606`) are `W.ItemNameOrLoad` text: coloured, no icon, no
  Shift-click.
- **Colours**: the chart colour (`:655`) and the gold category names and header cells (`:313`, `:591`) move to roles.
- **Fill**: fixed row counts (`MOVER_ROWS` 5, `CATEGORY_ROWS` 12, `LARGEST` 3, `:14-16`) become DataTable `fill`.
- **Notes**: the categories note ("Click a category…", now only in a tooltip, `:324`).
- `panel()` / `heading()` (`:121-138`) become `W.Panel` / `W.Heading`.
- **Compact** (`:405-444`): the artboard keeps the Segmented and drops Turnover. Lua swaps in a dropdown and hides
  movers. Follow the artboard where it's only layout.

### Shopping list (`ShoppingView.lua`) — ShoppingList

- "Search the AH" (`:102`) becomes primary. The title (`:99`) becomes a `W.PageHeading`, with the artboard's dim
  hint about right-click.
- `screenerControls` (`:151-166`) doesn't hide `v.category`, `v.signalsShort` or `v.more`, the compact-mode
  controls, so they probably stay over a list in a narrow window. Check this in game; if it's real, the fix comes
  with the step.
- `rowMoney` (`:38-40`) becomes `format = "money"`. Cost shows "—" when done (`:87`).
- The craft prompt's `recipe.name` (`:284`) becomes a link (the prompt text has links switched on, or an ItemLink
  above the input).
- The `|cff33ccffAME|r` prints (`:217`, `:281`, `:324`) become `ns.AME.Say`.
- The "Held by" tooltip (`:139-143`) renders through `Tooltip.AddRows`.

### Item tab (`ItemView.lua`) — Main, ItemCompact

- **Cards**: the market, stats and post cards (`:268-306`) become `card:SetContent`.
  - Market: a "Now" `big` money row, the change as a coloured text row ("▲ 56% above"), confidence as the note, and
    the signal as a SignalBadge plus the phase at the top right (`:1138-1159`).
  - Stats: five Pairs become rows. The supply trend gets ▲/▼ instead of a sign (`:1134`).
  - Post: the head row (`:1352`, `:1367`); "Normal · sells in ~3 h" as a `big` row; "You net, after the 5% cut" as
    its own money row (`:1376-1378`); the hours of Quick / Patient in the label, not the value (`:1368-1372`).
  - Lua only: the verdict card (`:268-274`) and "Hide from lists" (`:341-354`).
- **Item names**:
  - `UI.CraftInsteadText` (`:1304-1318`) puts a plain product name in the verdict, and AHSelling uses it too.
  - postWarn's "Make %s first" (`:1392`).
  - Search-suggestion menu entries (`:1441`) are `W.QualityText` only; they get the item tooltip.
- **Compact summary bar** (`:159-162`, `:1323-1336`): one joined string becomes a row of pieces (Money, the change,
  SignalBadge, "Post at", a Button), as in ItemCompact.
- **Colours**: the chart and legend colours (`:166`, `:219`, `:540`, `:637-659`, `:690`, `:728-733`, `:817`) become
  named entries in `W.COLORS.chart` with the artboard's values: market #4dd9c8, lowest #7fdc8a, MA #ffcc33, supply
  #6f7489.
- **Labels**: the watch button, Details and Legend get the design's ▾ / ▸ (`:154`, `:230`, `:310`).

### AH sell bar (`SellAssist.lua`) — SellBar

- "Fill price" (`fill`) becomes primary, replacing `SetSelected(true)` (`:235`). The design has three buttons; Lua
  has four (Normal, `:227-247`). Keep Normal, because the box can hold Normal's price, and say so to the user.
- The 2 px accent top border (theme accent; the vendor tone in the vendor case) is missing (`:203-205`).
- The title becomes a 16 px bold Money (`:251`). The confidence label and pips go on the right before the buttons
  (`:248-261`).
- The first-run hint "AME suggests…" (`:483`) loses the prefix.

### Arbitrage (`ArbitrageView.lua`) — Arbitrage

- **Sidebar cards** become `card:SetContent`:
  - Title: `item` + subtitle "Goblin AH → Horde AH" (`:237-241`, `:344-347`).
  - Cost: rows with `signed` and `total`, replacing the hand rule and font swaps (`:243-254`) and the hand sign
    colours (`:353-357`).
  - Data: the warn text becomes the note (`:256-260`, `:364-370`).
- "Search at the goblin AH" (`:269`) becomes primary. The extra `SetAlpha(0.5)` (`:376`) goes, since `SetEnabled`
  already fades it.
- Swap becomes "⇄" (`:121`). The age labels become "Data ≤ 3 days" (`:16-21`). The design's "Columns · N hidden"
  button needs `SetUserHidden` wiring like the screener (the DataTable has it); this one is a small feature (listed
  below).
- Margin (`:55`) is a signed coloured percent; the artboard shows plain "30%". Keep the sign colour unless the user
  says otherwise. It's information, not decoration.

### Portfolio (`PortfolioView.lua`) — Portfolio

- **KPIs**: `W.CardRow` (`:252-264`) becomes KpiCards. The "N auctions" font string (`:263-264`, `:483`) becomes
  `delta` with `deltaKind = "mute"`. Sold / bought (`:488`) becomes `copper2`, and signed amounts use `signed`.
- **Signal column** (`:32-43`) becomes a SignalBadge cell.
- **Item names**: the counterparties' "Mostly" column (`:113-121`) is an item name in plain text; it becomes a
  per-column item key (finding 7).
- **Labels** follow the artboard: "Export CSV" (`:305`); the period labels (`:224-229`) are a product question,
  because "Since reset" isn't what "Today" means.
- The tooltips (`:266-287`, `:365-367`) render through `Tooltip.AddRows`. The per-character rows duplicate the item
  tooltip's "Yours".

### Crafting tab (`CraftingView.lua`) — Crafting, CraftingProfessions, CraftingCrafters, CraftingQueuePage, CraftingRefine, CraftingRecipes

Shared to every page:
- **Toolbar** (`:847-945`) becomes `UI.CraftingToolbar`. The order is search, scope, checks, then actions on the
  right. Scope is kept on Find a crafter (profession), where Lua hides it (`:927-928`). The Dropdowns with neutral
  (`:873-880`) stay `W.Dropdown`, which already draws as a Button with an arrow.
- **Nav** (`:813-846`) becomes `UI.SideList`, with counts.
- **Page heading**: a gold title and dim subtitle above each table (`W.PageHeading`), missing now.
- **Table notes**: each page's artboard note (DataTable `note`).
- **Status**: one line per page instead of the same "Recorded: …" everywhere (`:1182-1186`). The text comes from the
  page's declaration.
- **Right column**: two fixed cards and 14 pooled Pairs (`:985-1022`) become a column of `card:SetContent` cards plus
  small DataTables (reagents, best earners, crafters, materials) per page. The card title's `UI.ItemLine` with no
  icon (`:986-991`) becomes `item`.
- **Actions**: the main action (`v.action`, `:1005`) is primary on every page, and the buttons sit at the bottom of
  the column (a spacer), not straight after the cards.

Per page:
- **Top earners**:
  - Faded rows for bind-on-pickup (`rowAlpha` unset).
  - The card's reagents (`:1392-1398`) are Pair labels; they become a reagents DataTable (item with count "2 (14
    held)" / "· buy" / "· vendor", Cost).
  - The "Selling it" card with an "AH cut and deposit" signed row and a total.
  - Lua only: the extra Cost / Sells for columns, Sells a day, cooldown rows. No Signal column in Lua; adding one is
    a feature (listed below).
- **Your professions**: the best earner as Pair text (`:1337`) becomes a "Best earners" DataTable (3 rows). The card
  title is gold "character · profession" (`:1332-1345`).
- **Find a crafter**: the card's crafter rows (`:1346-1357`) become a crafter DataTable (dot, name, skill, Whisper).
  The table's one-row-per-crafter vs the artboard's one-row-per-recipe is a product question.
- **Craft queue page**: the materials (`:1371-1378`, `PB.SourcesText` coloured text) become a DataTable with a
  `tag` column. "Missing to shopping list" becomes primary.
- **Sell or refine**: "Craft X" (`:608`, `:1425`) becomes a link (per-column item key). The option lines packing net
  and gain into one value (`:1424-1431`) become a card per option, with rows and a total.
- **Recipes to buy**: "Makes" and "Teaches X" (`:1440`, `:1445`) become links. The learner rows (`:1460-1466`) stay
  as rows (Lua only; the artboard has a note). Search the AH becomes primary.

### Leveling (`LevelingView.lua`) — CraftingLeveling

- **Toolbar**: on `UI.CraftingToolbar` with `extra` (the profession / target pickers and goal Segmented,
  `:338-364`). Search shows if the page filters by it (the artboard has one), which needs a filter; otherwise it
  stays hidden.
- **Header**: `W.CardRow` of 5 StatCards (`:366-389`) become KpiCards with `big` signed values. "Other goals, net"
  (with its hover) stays (Lua only).
- **Craft column** (`:276-287`): plain `itemName` text becomes an item column. Learn / train rows (`:207-224`,
  `:283`) get the recipe item as a link (per-column item key) and the learn tone.
- **Card**: the colour bar stays in the title card. Its RGBs (`:396`, `:403`) go to `W.COLORS.skill*`, the same
  values. The reagents as "%d name" labels with empty values (`:495-497`) become a reagents DataTable. "Net for this
  step" becomes a `total` row.

### Profession bar and craft queue panel (`ProfessionBar.lua`) — ProfBar, CraftQueue

- **The bar** (`:381-477`):
  - Line 1 (one font string, `:458-468`) gets the sales rate on the right and a SignalBadge.
  - Line 2's batch text (`:469-475`) gets its ore as a link (inline links).
  - "Add to shopping list" opens a menu and gets ▾ (`:418`).
  - The second "Queue (n)" toggle (`:427-430`) has the same label as the primary button; it's renamed (e.g. "Show
    queue (n)"). That's a label change for the user to confirm.
- **Recipe list**: the profit font strings on the game's rows (`:975-986`) get "no price" for unpriced rows (blank
  now) and the artboard's footnote.
- **Queue panel** (`:588-939`):
  - Make / Buy becomes `W.Segmented` (`:697-700`, `:825-826`).
  - Source tags become `W.Tag` (`:664-678`, `:875-889`); `carried` dead code goes.
  - The step's reagent names (`:767`, `ItemCache.Name`, no colour) and the to-do lines (`:745`, `:920-921`, one hover
    over the whole line) become inline links.
  - The step sub-line becomes two lines, as the artboard does (`:751-774`).
  - The redundant `showItem` then re-set (`:812-814`) goes.
  - The two artboard notes (source order; what "Craft next" skips).
  - The `|cff33ccffAME|r` prints (`:237`, `:338`, `:353`) become `ns.AME.Say`.

### Who can make it (`CraftersView.lua`) — Crafters

- 16 fixed font-string rows with Whisper buttons (`:98-111`) become a DataTable with `fill` and a `button` column.
  A row is the dot, name, note (guild / "(your alt)" / trusted), seen, skill, and Whisper or "log in there".
- The recipe line `W.Color("gold", name)` (`:134`) becomes a link where the recipe has an item (enchants have none).
  The "•" text bullet (`:136`) becomes the coloured dot.
- The "Item or enchant" label over the input, the header meta and the footnote come from the artboard.
- `V.MadeBy` (`:174-197`, one comma-joined line) becomes a TooltipBlock section ("Made by · with Shift", a line per
  name with a dot, "+2 in your guild").

### Item tooltip (`Tooltip.lua`, `Launcher.lua`) — TooltipTrade(+Shift), TooltipGear(+Shift), TooltipCompact, Tooltips

- **Order**: recipe rows and recipe sources are added above the gap, outside the block (`:451-477`). They move into
  the block as sections, after the signal line.
- **Header**: the house in `brand` (`:93-102`) becomes gold, as the artboard has it.
- **Notice**: the warn (!) icon is missing (`:141-144`).
- **Section headings**: `section()` (`:43-45`) becomes `W.TipSection`: small caps, 10 px grey, with a gap above.
- **Disenchants into** (`:171-181`): plain `o.name` (`:296`) becomes a quality-coloured name. Columns are % right,
  count and name and "×" each, then the total, with a rule above "Expected".
- **Yours** (`:184-199`): becomes a grid with bags / bank / AH column heads and "·" for empty cells, plus the heading
  note "43 on 3 characters".
- **Auction houses** (`:202-222`): column heads "market" / "you get" instead of "market > net".
- **Price**: the labels are lower-case ("lowest", "score", "data", `:224-246`); they get the artboard's
  capitalisation. Splitting into Price and Data is layout.
- **Item names**: "Makes" (`:432`, `W.ItemLabel`) becomes quality-coloured.
- **"AME" text**: "Hold Shift for more AME data" (`:164`) becomes "Hold Shift for more".
- **Launcher** (`:86-112`): the minimap tooltip's greys (`:88`, `:152-160`) become roles. "Top buy signals" becomes
  gold, and the items (`:105`) become quality-coloured. "AME notifications" (`:138`) loses the prefix.
- The artboards disagree on 3 vs 5 confidence bars (ItemLink: 3; TooltipBlock: 5); keep `W.Confidence`'s 3 unless
  the user picks 5.
- Values the data core doesn't have yet (Post at, sell chance, deposit on gear, reason sentences for the signal) are
  features; see the list below.

### Settings and Sharing (`SettingsView.lua`, `SyncView.lua`) — Settings, Sync

- **Section nav** (`SettingsView.lua:63-83`) becomes `UI.SideList`.
- **Cards** become `UI.SettingsCard`:
  - The local helpers (`:129-157`) move into it.
  - SyncView's hand-built cards (`:123`, `:194`, `:240`) use it.
  - The protocol dropdown moves to the right like every field (`SyncView.lua:143-160`).
  - The data action buttons laid out by x/y (`FlowActions`, `:369-381`) become a `{buttons}` row that wraps.
- **Labels**: "Show AME prices in item tooltips" (`:210`) becomes "Show prices in item tooltips". "...and close with
  it" becomes "…and close with it".
- **Freshness tiles** (`SyncView.lua:62-74`) become KpiCards.
- **Lua only**: the Data, Selling and Tooltips & charts sections; protocol, recipe sharing, the Requests list; the
  section title toolbar row.

### Guide (`Help.lua`) — Guide

- **Sidebar** (`:946-981`) becomes `UI.SideList`, with "Glossary · N terms" as the heading note.
- The article area isn't skinned (`slots.main`, `:1071`); it goes in a `W.Panel`, as the artboard has it.
- Paragraph font (`:1088`, GameFontHighlight) goes down to the small body font the artboard uses. Check this in game
  for readability before committing to it.
- The status line keeps the credit (Lua only).
- The examples' hard-coded colours (`:180`, `:864-872`) become roles. The SellBar example's "AME" tag (`:826`) follows
  whatever the sell bar does.

### AH Shopping tab (`AHShopping.lua`) — AHShoppingTab

- **Sidebar** (`:303-329`, `:707-727`; a fixed 24 lines, `:404`) becomes `UI.SideList`, which fills the height.
  `T.SIDE_W` becomes `UI.SIDEBAR_W`.
- **Listings** (`:493-515`, `cell()` `:162`, its own stripes `:501`) become a DataTable: Each (money, left), Qty,
  Time left, and "yours" as a text column (`:816`). Selected row; Buy under it. The commodity quantity input, the
  confirmation and the per-row Buy for non-commodities stay (Lua only). Time left is new data; check that the
  listing info has it (the game's results do).
- **Item names**: the listings title (`:800`, `W.ItemLabel`) becomes a `W.ItemLink`.
- **Filters grid**: the hand-placed pixels (`:181`, `:259`, `:294`, `:299`) get a small grid (label over control),
  with the two checks on their own row as in the artboard.
- `makePanel` / `T.Panel` (`:170-178`) becomes `W.Panel`.
- **"AME" text**: "make one in the AME window" (`:702`) loses "AME" ("…in the main window").

### AH Selling tab (`AHSelling.lua`) — AHSellingTab

- **Form header** (`:227-233`, `:501-502`): an icon and `W.QualityText` with no hover become a `W.ItemLink` with the
  count.
- **Hints**: make / vendor / DE are glued to the name by `suffix` (`:176-186`). They become their own text column
  between Item and Worth (make in warn, DE in the disenchant tone, vendor dim), with the product in "make X" as a link
  (per-column item key, `:179`, `:549`).
- **Deposit / You get**: one font string each (`:291-296`, `:538-544`) become label-left / money-right rows (a
  card's rows).
- **Info line**: the signal (`:509`) becomes a SignalBadge.
- **Notes**: the hand-placed empty message (`:215-218`) becomes `t:SetMessage`. The sale note (`:346-349`) becomes
  DataTable `note`, with the artboard's second sentence. The bag table's "Worth: …" note.
- **Post**: full-width (`:300-304`); the artboard has it 80 wide at the bottom-left. Keep it full-width: it's the
  panel's one action and easier to hit. Say so to the user.
- **Widths**: the list is 260 (`S.LIST_W`, `:14`); the artboard has 300. The form is 300; the artboard has 280.
  Follow the artboard.

### Vendor panel (`VendorPanel.lua`) — VendorPanel

- Width 380 (`V.WIDTH`, `:15`) becomes 500, as in the artboard. Check it in game next to the merchant frame at 1080p
  and at the smallest scale.
- The title and subtitle are stacked (`:158-164`); they go on one baseline (`W.PageHeading`).
- Buys (`:178`): "25 (5 × 5)" all dim after the number.
- The footer note from the artboard.

## (c) Commits, in order

Every step is one commit to main. It ends with `busted`, `luacheck Core spec`, `stylua` and
`lua5.1 scripts/locale-keys.lua` passing, all run in WSL; the locale script is run to write, then committed with the
step. Widget steps add or extend `spec/widgets_spec.lua` (pure helpers) or a new `spec/ui_widgets_spec.lua` (frame
widgets, on `spec/helpers/wow.lua`'s frame stubs; extend the stubs where a widget needs `SetHyperlinksEnabled`,
`OnHyperlinkEnter` or `SetColorTexture` on new kinds). View steps keep the integration handles from finding 10 and
change no expected numbers. New visible strings go through `L[...]`.

### Widgets (no view changes beyond the one consumer each needs to prove it)

1. **Primary look.** `W.Primary` draws a solid accent fill at a shade with 4.5:1 for a white label on every theme;
   `W.SetTheme` re-tints it. `W.Button` `opts.color` for a label tone. Spec: contrast for white on the primary fill
   for Alliance, Horde and Neutral, in both palettes. Replace the direct `SetSelected(true)` stand-ins
   (`SellAssist.lua:235`, `ArbitrageView.lua:269`) and add `W.Primary` to every main action the artboards mark
   (Crafting, Leveling, Shopping list, Arbitrage). This is the one widget step that touches many views, because the
   look only shows once callers use it.
2. **ItemLink.** `W.ItemLink(parent, opts)` (icon, name, count, conf, star, font) and inline links: `W.LinkText(key,
   count)` returning an `|Hitem:…|h` string in the quality colour, and `W.EnableLinks(frame)` wiring hover (the item
   tooltip) and modified click (`W.ItemLinkClicked`). Spec: `LinkText` text and colour, a click with Shift calls
   `HandleModifiedItemClick` with the link, and a plain click opens the item. First consumers: the AH Shopping
   listings title, the AH Selling form header.
3. **DataTable: item linking and the new cell types.**
   - Modified click on an item row links the item, before `opts.onClick`. The screener's own Shift-click rule follows
     the user's answer below.
   - `bare`, `note`, `format = "signedMoney"`, `share` (`col.max`).
   - Per-column item keys (`col.item = function(d)`), each with its own icon and hover region.
   - A `button` column with per-row label and variant.

   Spec: new `spec/datatable_spec.lua` covering sort, `fill` row counts, a note's space, share bar widths, and the
   modified click calling `HandleModifiedItemClick`. Integration specs on `marketView.table` keep passing.
4. **Signals.** `W.SignalBadge(parent)` (pill and word) and a DataTable `signal` cell drawing it; `W.SignalText`
   (alias of `W.SignalGlyph`); `W.SignalFilter(parent, opts)` (`signals`, `short`). Spec: contrast of each badge's
   word on its pill in both palettes (like the existing inverted-signal test, `widgets_spec.lua:15-29`).
5. **Tag.** `W.Tag(parent)` with `other | ah | made | vendor`, and the DataTable `tag` cell. Colours in
   `W.COLORS.tag`; `made` follows the accent. Spec: contrast per kind on each theme.
6. **Card content.** `card:SetContent{…}` on `UI.Stack:Card` (`Shell.lua:134`): pooled rows (money / signed /
   total / big / color / term / label item), item or title, subtitle, note; `card:Fit` measures it. Spec: rows
   reuse their font strings across calls; a total row has a rule; hidden rows don't add height.
7. **KpiCard.** `W.KpiCard` and `W.CardRow` building it; `:SetCompact`. Spec: the delta tone per `deltaKind`, the
   rise / fall bar's proportions, compact hiding the note. Remove `W.StatCard` in the last view step that uses it.
8. **SideList.** `UI.SideList(sidebar, opts)` in `Shell.lua`: entries, kinds, indent, notes, counts; fills and
   scrolls; the theme repaint inside it. Keeps `.lines`. Spec: lines grow with the height, the selected line's
   colours, a click passes the entry and button.
9. **Panels, headings, SettingsCard, menus.**
   - `W.Panel` and `W.PageHeading`.
   - `UI.SettingsCard(stack, title, rows)`.
   - `W.Menu` separators and submenu marks.

   Spec: SettingsCard row kinds produce controls bound to the setting key (a check toggles `ns.Settings`).
10. **TooltipBlock model.** `Tooltip.Lines` gains `sections` and bits (item names quality-coloured, warn icon,
    confidence), and `W.TipSection`. `Tooltip.AddRows` renders sections. Rows keep `{left, right, middle}`.
    `tooltip_spec`'s cases pass unchanged, and new cases cover a section with column heads and an item bit.
11. **CraftingToolbar.** `UI.CraftingToolbar(v)` in `CraftingView.lua` with the per-page declaration (search, scope,
    checks, actions, extra) and per-page status text. CraftingView's `LayoutToolbar` moves onto it in this step
    (its only consumer), with no visible change except the order (search first) and the actions slot.

### Views (one per commit; each uses only widgets from steps 1–11)

12. **Window shell**: the active tab look, the busy text on the right, `AHShopping`'s `T.SIDE_W` → `UI.SIDEBAR_W`.
13. **Market screener + menus** (`MarketView.lua`, `Watchlists.lua`).
14. **Market Overview** (`MarketOverview.lua`).
15. **Shopping list** (`ShoppingView.lua`).
16. **Item tab** (`ItemView.lua`), including the named chart colours.
17. **Sell bar** (`SellAssist.lua`).
18. **Arbitrage** (`ArbitrageView.lua`).
19. **Portfolio** (`PortfolioView.lua`). `W.StatCard` goes once Portfolio, Overview, Leveling and Sync no longer use
    it; this is the last of those, unless the order changes.
20. **Crafting tab frame**: `CraftingView.lua` nav (SideList with counts), page headings, notes, primary actions,
    the right column's card / DataTable structure.
21. **Crafting pages' cards**: Top earners, Your professions, Find a crafter, Craft queue page, Sell or refine,
    Recipes to buy (`CraftingView.lua`). This step can split by page if it grows past ~300 changed lines.
22. **Leveling** (`LevelingView.lua`).
23. **Profession bar and craft queue panel** (`ProfessionBar.lua`).
24. **Who can make it** (`CraftersView.lua`), with `V.MadeBy` as a tooltip section.
25. **Item tooltip and minimap tooltip** (`Tooltip.lua`, `Launcher.lua`).
26. **Settings and Sharing** (`SettingsView.lua`, `SyncView.lua`).
27. **Guide** (`Help.lua`).
28. **AH Shopping tab** (`AHShopping.lua`).
29. **AH Selling tab** (`AHSelling.lua`).
30. **Vendor panel** (`VendorPanel.lua`).
31. **Guard.** `spec/toolchain_spec.lua` checks:
    - no `W.QualityText(` next to `W.ItemLabel(` / `ItemCache.Name(` in a view outside Widgets (an item name drawn as
      text);
    - no `SetSelected(true)` used as a primary stand-in;
    - no `|cff33ccffAME` in `Core/UI/`;
    - no new hand-made sidebar lines (a `rowSelected` fill outside `Shell.lua` / `DataTable.lua` / `Widgets.lua`).

    Same idea as data-core step 12's guard.

Steps 1–11 depend only on each other where named (3 needs 2 and 4–5 for its cell types; 6 uses 2; 11 uses 8). Views
13–30 are independent of each other once their widgets are in, so they can go in any order the user prefers. The
order above goes from the most-seen screens to the least.

## (d) Risks to check in game

- **Inline item links in font strings.** `SetHyperlinksEnabled` on a plain frame (as `Help.lua:1077` does) has to
  fire `OnHyperlinkEnter` / `OnHyperlinkClick` on the Forever client for `|Hitem:` links, and Shift-click has to put
  the link in an open chat box. Test it in step 2 before any view relies on it. Fallback: flow `W.ItemLink` frames in
  a row (more frames, no wrapping).
- **Modified click on DataTable rows.** `HandleModifiedItemClick` with no chat box open may try on the item (Ctrl)
  or do nothing (Shift). Check that the screener's Shift-click search still works at the AH, and decide which wins
  when the chat box is open.
- **Primary fill contrast.** The theme-shaded accent behind white text on all three themes and with the colour-blind
  palette, and next to a selected Segmented button (they must still look different).
- **Frame counts.** SignalBadge cells, Tag cells and per-column item icons add frames per row. On a screener with 40
  rows at a tall window, check that scrolling stays smooth (`/framestack`, the frame rate while wheel-scrolling).
- **Fill tables in small panels.** `bare` DataTables in Overview and the Crafting right column must not overflow
  their panels at compact sizes, and their row count must follow the panel when the window is resized while hidden
  (DataTable already re-checks its size on Render, `DataTable.lua:523-530`).
- **SideList scroll.** The Market sidebar pages itself with the wheel and has no scrollbar now (`MarketView.lua:327`,
  `:370-374`). Check that a long category tree with many lists scrolls the same way, and that the AH Shopping sidebar
  (24 fixed lines now) fills a tall AH frame.
- **Tooltip width.** Column heads and the bags / bank / AH grid widen the tooltip. Check it next to the game's own
  comparison tooltips, with `Tooltip.AddRows`' secret-width fallback (`Tooltip.lua:554-560`) still taking over when
  widths can't be read.
- **Vendor panel at 500 px.** With the merchant frame and the bags open, at 1080p and at a high UI scale.
- **AH tabs.** Blizzard's tab template (`AHShopping.lua:959`) next to the new widgets. Also check that Auctionator
  being loaded still hides the tabs.
- **Theme switches.** Change the house in the title bar and check primary buttons, Tags (`made`), SideList selections
  and badges re-tint without a reload.
- **Guide font size.** A smaller body font is easier to scan but may be hard to read at default scale; check it
  before committing step 27's font change.
- **Colour-blind palette.** Badges, Tags, KpiCard deltas and the share bar with `colorBlind` on.

## Coordination with data-core

The agreed order is data-core 1–7, this plan, then data-core 8–11. Overlaps:

| data-core step | Same files as this plan | How they fit |
|---|---|---|
| **1. Formatting** (in progress) | `Widgets.lua` and eight views | This plan uses its helpers and adds no formatting of its own: `W.SignedMoney{full, zero, tint}` for signed Card / KpiCard rows, `W.CutPct` for "the 5% cut" labels, `W.ItemLabel` only as `W.ItemLink`'s fallback text. |
| **2. Events bus** | Every view's refresh (`UI:OnIndexReady`, `Window.lua:449-467`); `Professions.onChange` (`CraftingView.lua:1042`), `Shopping.onChange` (`AHShopping.lua:560`) | Views here subscribe the way step 2 leaves them. `UI.SideList` gets its counts by being re-fed on `ShoppingChanged` / `WatchChanged`, with no listener of its own. |
| **3. ItemCache facts** | `W.ItemNameOrLoad`, `DataTable:RenderWhenLoaded` (`Widgets.lua:796-918`, `DataTable.lua:494-`) | `W.ItemLink` and the per-column item cells (steps 2–3 here) are built on `ItemCache` plus `NamesChanged` as step 3 leaves them, with no polling of their own. The four view wrappers of `ItemNameOrLoad` that step 3 removes don't come back. |
| **4–7. Quote, Recipes, Holdings, CraftModel** | `CraftingView.lua` (`UI:CraftingEnv`, `CraftingModel`, `recipeFor`), `ProfessionBar.lua`, `LevelingView.lua`, `Tooltip.lua`, `AHSelling.lua` | They're done before this plan starts, so steps 20–25 and 29 rebuild views that already read the core. Don't move data code in a UI step. If a UI step finds a number still computed in a view, it notes it for data-core 8–11. |
| **8. One Crafting env** | `ProfessionBar.lua` (`PB.Craft`), `Tooltip.lua` (`RecipeLines`) | Comes after steps 23 and 25 here, which change how recipe rows are drawn (a tooltip section) but not their numbers. Step 8 then only changes the values its specs name. |
| **9. One recipe order** | `ProfessionBar.lua`, `LevelingView.lua`, `Tooltip.lua` | Same: after steps 22, 23, 25. |
| **10. Usable holdings** | The tooltip's "You have" / "Yours" (`Tooltip.lua:114-117`, `:184-199`), ShoppingView's "Held by", the queue's source Tags | Step 25 here draws "Yours" as a bags / bank / AH grid from the fields `Tooltip.Lines` gets now. Step 10 changes which places are counted, not the grid. |
| **11. Derived fields** ("Sales/day" → `soldPerDay`) | Every "Sales/day" column and label (`MarketView.lua:62`, `ArbitrageView.lua:70`, `PortfolioView.lua:44`, `ItemView.lua:288`), the tooltip's rate | The artboards say "Sells/day". **Rename the labels in data-core step 11**, when the columns switch to `soldPerDay`, so the locale keys change once. This plan leaves the labels alone. |
| **12. Guard** | `spec/toolchain_spec.lua` | Step 31 here adds UI rules to the same spec; whichever lands second extends the other's block. |

## Questions for the user

These come from the artboards disagreeing with each other or with the rules. Each has a recommendation; the steps
above follow the recommendation until told otherwise.

1. **Shift-click in the Market screener**: today it searches the AH (at the AH); the item-link rule says it links
   the item. Recommended: link when a chat box is open, search the AH otherwise.
2. **Selected signal filter button**: Lua inverts it (filled with the signal's colour, dark text), and
   `widgets_spec` guards that contrast. SignalButton draws the ordinary selected Button with the label in its tone.
   Recommended: keep Lua's inverted look; it reads better at a glance. The artboard's words are Buy / Hold / Sell
   where Lua's are BUY / HOLD / SELL; keep the capitals to match the badges.
3. **Settings in the title bar**: a gear (Lua) or a text tab between Item and Guide (TitleBar artboard)?
   Recommended: keep the gear (it saves tab width in compact).
4. **Crafting tab visibility**: TitleBar's comment says it shows only when switched on in Settings; the Crafting note
   says it's always there; Lua always shows it. Recommended: always there, as now. The TitleBar artboard's comment is
   stale.
5. **"AME" in the sell bar's tag** (`SellAssist.lua:250`): the artboard has it, but the rule says no prefixes.
   Recommended: drop it; the bar sits under the game's sell frame and reads fine without it.
6. **Confidence bars**: 3 (ItemLink, Lua) or 5 (the tooltip artboards)? Recommended: 3 everywhere.
7. **Portfolio period labels**: "Today" (Lua) vs "Since reset" (artboard) mean different things. Recommended: keep
   Lua's until the period itself changes.

## Artboard features not built yet

These appear in the artboards but are new behaviour or new data, so they are separate commits after (or between) the
steps above, each only when the user asks for it:

- **Tooltip**:
  - "Post at (Normal)" with sell chance, and the deposit on gear.
  - Reason sentences for the signal ("disenchanting beats listing by 34s").
  - The goblin AH's sales per day and data age.
  - "(alt there)".
- **Crafting pages**:
  - Top earners' Signal column and Queue action.
  - Your professions' unrecorded-character rows.
  - Find a crafter's one-row-per-recipe table with the recipe item row.
  - The Craft queue page's To-do table, per-step Buy / ✕ and totals heading.
  - Refine's "Queue the smelt".
  - Leveling's "Queue the steps" and its search.
- **Profession bar**: sales rate and signal on line 1; "no price" plus the footnote on the recipe list.
- **Who can make it**: the formula on the AH with its price; the header meta ("recipes from 38 players").
- **Arbitrage**: a Columns button (hide columns, as the screener does).
- **AH Shopping**: the Time left column, if the listing data needs more than drawing.
- **Market Overview**: largest items as "18,400 ×" with "capped from X".
- **Sync**: "next announce in 8 min" in the status.
