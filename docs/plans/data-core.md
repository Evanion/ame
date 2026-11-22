# Data core: every number computed once, every view reads it

Status: plan (Nov 2026). Nothing here is built yet. It follows a2d5122, which fixed one disagreement (the sales rate
corrected for real auction outcomes in some tables but not others) by estimating it once in `Core/Index.lua`
(`SellThrough.Prior` / `SellThrough.Estimate`). This plan makes that kind of fix the default: one core computes each
number, the UI formats and draws it, and there is nowhere else to compute it.

Line numbers are as of a2d5122.

## Why

Today a price, a rate, a count of what you hold or a recipe's yield is worked out wherever it's needed. The pieces
mostly call the same primitives (`Settings:AuctionCut`, `Arbitrage.Deposit`, `ItemCache.Get`), but each call site
picks its own house, its own price (raw or capped, index or fresh search), its own places to count and its own
recipe source. Every new view adds another copy, and every fix has to find all of them. The findings below are the
copies that exist now; several already show different numbers for the same item on two screens.

## The current flows (short map)

```
scans / searches / sync ──> Store (history, books) ──> Index.lua: BuildIndex ──> index.items[id] = summary
                                                          │  Analytics.Summarize (market, avg*, sellRate, signal)
Posting (auction outcomes) ──> SellThrough ───────────────┤  SellThrough.Apply / Estimate (sellRate, value)
ItemCache (vendor price) ─────────────────────────────────┤  Analytics.VendorCheck / DisenchantCheck
                                                          └─> SetIndex ──> UI:OnIndexReady (hard-coded switch)

Reading the summary, each with its own derived numbers:
  MarketView / ItemView / Tooltip / AHSelling   s.market, s.sellRate (raw), own net-after-cut
  ArbitrageView ──> Arbitrage.Find              s.min / s.market (uncapped), cut; deposit added in the view
  PortfolioView ──> Portfolio.Build             s.value or s.market (gross), raw sellRate
  MarketOverview ──> MarketStats                capped price, SoldPerDay = min(sellRate, qty)
  CraftingView ──> UI:CraftingEnv ─┐
  ProfessionBar ──> PB.Craft ───────┼─> Crafting.New(env)  each env built by hand, differently
  Tooltip ──> RecipeLines ──────────┘       Crafting:Price (capped), NetSale (cut + deposit), SalesPerDay (min)
  LevelingView ──> Leveling.Plan (uses CraftingView's env + its own deValue)
  SellAssist / ItemView post box ──> Posting:Advice ──> Pricing (sellRate, churnRate), own net-after-cut

Holdings: Trading scans ──> AME_DB.holdings / guildBanks
  Trading.Held · Shopping.Progress · Portfolio.Merge · PB.heldTotal · CraftQueue heldBy · CraftingView /
  LevelingView loops · AHSelling.ScanBags (a live walk of its own)  — six different "what you have"

Recipes: live C_TradeSkillUI · AME_DB.crafting catalog · shipped CraftingData · synced AME_DB.crafters
  PB.Recipe · recipeFor (CraftingView) · Leveling candidates · Tooltip.RecipeLines — four "recipe by ID"
  producerMap (PB) · CraftingModel producers · Crafters.RecipesFor — three "what makes this item"
```

## Findings

Each finding lists where the copies are and which numbers can disagree. Confirmed means read in the code, with the
disagreement traced through; everything here is confirmed unless marked otherwise.

### A. Prices and market numbers

**A1. Four hand-built Crafting environments.** `UI:CraftingEnv` (`Core/UI/CraftingView.lua:120-175`), `PB.Craft`
(`Core/UI/ProfessionBar.lua:100-125`), `Tooltip.RecipeLines` (`Core/UI/Tooltip.lua:409-427`) and Leveling (through
CraftingView's env plus its own `deValue`, `Core/UI/LevelingView.lua:138-148`). They differ in:

| | CraftingView | ProfessionBar | Tooltip |
|---|---|---|---|
| house | `CurrentHouse`, Neutral -> `UnitFactionGroup` (:122) | `FactionShard` (:105-106) | `UnitFactionGroup` (:408) |
| cut | `Settings:AuctionCut` | `Settings:AuctionCut` | hand-rolled from `cutNeutral`/`cutFaction` (:409) |
| price | fresh search's cheapest listing, else index (:128-150) | index only | index only |
| `sellable` (BoP products) | yes (:164-168) | no | no |
| `producers` (craft the parts) | yes (CraftingModel) | no | no |

So the same recipe has a different cost and profit in the Crafting tab, on the profession bar and in the recipe
tooltip: the tab prices from a fresh search and crafts ore into bars; the bar and tooltip buy the bars and price from
the day's average; the bar and tooltip count a bind-on-pickup product as sellable.

**A2. "What one listing nets" has five formulas.**
- `SellThrough.Net` (`Core/SellThrough.lua:171-179`): cut, deposit lost only as often as listings fail. Used by the
  VENDOR / DE signals (`Core/Analytics.lua:224-229`).
- `Crafting:NetSale` (`Core/Crafting.lua:59-74`): capped price, cut, deposit always lost, vendor if better.
- `DisenchantSignals` `netSale` (`Core/Index.lua:99-106`): uncapped market, cut, deposit always lost, no vendor.
- `AHSelling S.Worth` (`Core/UI/AHSelling.lua:42-48`) and the tooltip's house rows (`Core/UI/Tooltip.lua:323`):
  market after the cut, no deposit, no cap.
- `Arbitrage.Find` (`Core/Arbitrage.lua:34-37`): market after the cut; the view subtracts a deposit afterwards
  (`Core/UI/ArbitrageView.lua:84-93`, `:423-438`, re-sorting by "net" itself).
Disagree: the Sell tab's "worth", the Crafting tab's "sell raw" (refine page), the VENDOR signal's `vendorNet` and the
tooltip's per-house net are four different numbers for one stack.

**A3. Price per unit after the cut and deposit, written twice in the UI.** `Core/UI/ItemView.lua:1373-1375` and
`Sell.Net` `Core/UI/SellAssist.lua:196-200`, same formula, different house (viewed shard vs current shard).

**A4. Capped vs raw market price.** `Crafting:Price` (`Core/Crafting.lua:45-56`) and MarketStats (`Core/MarketStats.lua:121`,
`:369-372`) cap at `outlierFactor x avg30`. Arbitrage, Portfolio, AHSelling, Tooltip, ItemView and the DE signal use
`s.market` uncapped. A fantasy listing at the other house makes an arbitrage route and inflates portfolio value while
Crafting ignores it.

**A5. Sales per day: one clamp, applied in two places only.** `Crafting:SalesPerDay` (`Core/Crafting.lua:35-42`, nil
without a rate) and `MarketStats.SoldPerDay` (`Core/MarketStats.lua:110-117`, 0 without a rate) are the same
`min(sellRate, qty)`. Every other "Sales/day" column shows raw `s.sellRate`: Market (`Core/UI/MarketView.lua:62`),
Arbitrage (`Core/Arbitrage.lua:60`), Portfolio and its days-to-sell (`Core/Portfolio.lua:79-80`), the item page
(`Core/UI/ItemView.lua:1137`, `:1277-1281`), the tooltip (`Core/UI/Tooltip.lua:129-133`, with its own number
formatting), the Sell tab (`Core/UI/AHSelling.lua:513-514`). An item with 3 listed and a rate of 40 shows 3/day in
Crafting and 40/day everywhere else.

**A6. Two "fresh price" overlays.** CraftingView's book copy (cheapest listing of a search under an hour old,
`UI.CRAFT_FRESH_BOOK`, no outlier check, `Core/UI/CraftingView.lua:128-150`; `qty` stays the index's unless it has
none) and `Posting:FreshMarket` (newest scan's market under 48 h, rejected if `outlierFactor` off avg7,
`Core/Posting.lua:134-145`). Right after a search, the Crafting tab and the post box price the same item differently,
and the profession bar (no overlay) differs from both.

**A7. Three disenchant values.** `Tooltip.Disenchant` values materials at gross market (`Core/UI/Tooltip.lua:280-306`);
the DE signal at market after the cut and deposit (`Core/Index.lua:94-123`); Leveling at `craft:NetSale` (capped, vendor
fallback, `Core/UI/LevelingView.lua:138-148`). All three repeat the `GetItemInfo` quality/level lookup.

**A8. Portfolio worth vs everything else.** `Portfolio.Build` values a unit at `s.value or s.market`
(`Core/Portfolio.lua:55-57`): gross, before the cut. `Portfolio.Listed` nets after the cut (`:39`). The Sell tab nets
after the cut. The portfolio total is the only "what is it worth" that ignores the cut.

**A9. Which house prices things: five resolutions.** `UI:CraftingEnv` (:122), `PB.Craft` (:105), Tooltip (:408),
AHSelling's `cut()` (`Core/UI/AHSelling.lua:73-75`), `Sell.Net` / ItemView (shard-derived). Arbitrage keeps
`self.arb.buy/sell` (`Core/UI/ArbitrageView.lua:99-101`).

### B. Holdings ("what you have")

**B1. Six "have" formulas.**

| Site | Places counted | Characters |
|---|---|---|
| `Trading.Held` `Core/Trading.lua:196-238` (tooltip "You have") | bags, bank, AH, mail, guild bank | this market |
| `Shopping.Progress` `Core/Shopping.lua:129-143` (Shopping, AH Shopping, VendorPanel, MarketView) | bags, bank | every market |
| `heldTotal` `Core/UI/ProfessionBar.lua:155-158` | bags, bank, mail, guild bank | this market |
| `CraftQueue` `heldBy` `Core/CraftQueue.lua:29-42` | yours: bags, bank, mail; alts: bags, bank (alt mail dropped) | this market |
| `CraftingModel` `Core/UI/CraftingView.lua:282-291`, LevelingView `:167-173` | bags, bank | every market / one char |
| `Portfolio.Merge` `Core/Portfolio.lua:13-29` | bags, bank, AH | every market |

**B2. The craft queue's shopping list asks for too much.** `QueueToShopping` sets need = to buy + `heldTotal`
(`Core/UI/ProfessionBar.lua:230`), which counts mail and the guild bank; `Shopping.Progress` then subtracts only bags
and bank (`Core/Shopping.lua:132`, `:148`). "To buy" in Shopping, AH Shopping and the vendor panel's buy amount come out
at the real shortfall plus whatever is in your mail and guild bank.

**B3. Market scope.** `Held` and `heldTotal` keep to your market (`Core/Trading.lua:202-204`); Progress, CraftingModel
and Portfolio.Merge count characters on every realm. An alt on another market makes a list "done" that the queue
still says to buy for.

**B4. Two bag walks.** `Trading` `countBags` (`Core/Trading.lua:64-92`, skips bound items) and the Sell tab's live
`S.ScanBags` (`Core/UI/AHSelling.lua:78-`). Bound items never count as held anywhere cached (`Core/Trading.lua:86`), so a
bound reagent is always "missing" for the queue.

**B5. Bank tabs.** On clients with `CharacterBankTab_*`, `Trading.BankBags` returns before the reagent bank
(`Core/Trading.lua:109-116`). No warband / account bank is read anywhere. (Unverified in game: whether Forever exposes
an account bank at all. Check before building on it.)

**B6. Shortfall maths, five times.** `Shopping.lua:148`, `ProfessionBar.lua:136` (`PB.Summary`, full holdings per
recipe, ignoring what the queue already claimed), `CraftQueue.lua:144-168` (a shared stock), `Leveling.lua:139-143` and
`:195-199`, `AHShopping.lua:65-68`. The bar's "missing" for a recipe differs from the queue's for the same reagents.

**B7. Four `BAG_UPDATE_DELAYED` listeners.** `Main.lua:739-743`, `ProfessionBar.lua:1062`, `VendorPanel.lua:249`,
`AHSelling.lua:594`.

### C. Recipes and who can craft

**C1. Four "recipe by ID".**

| Where | Sources, in order | yield (`made`) | cooldown |
|---|---|---|---|
| `PB.Recipe` `Core/UI/ProfessionBar.lua:23-57` | live, cache, catalog — never the shipped data | (min+max)/2 | none |
| `recipeFor` `Core/UI/CraftingView.lua:92-116` | that profession's catalog, shipped | avg / shipped | yes |
| Leveling `candidates` `Core/UI/LevelingView.lua:79-88` | shipped, overlaid with the catalog | avg / shipped | yes |
| `Tooltip.RecipeLines` `Core/UI/Tooltip.lua:432-436` | shipped only | shipped | none |

Disagree: a queued recipe nobody has scanned drops out of the queue (`Core/CraftQueue.lua:89-91`) while the Crafting
tab shows it; the tooltip's yield is the shipped one even with a scan; the bar and queue never get a cooldown, so
`canPerDay` (`Core/Crafting.lua:163-165`) is never set there. `recipeFor(nil, spell)` for Recipes to buy
(`CraftingView.lua:509`) always skips the catalog. Shipped enchants have `made = 0`, which `recipe.made or 1` lets
through. `PB.recipeCache` is never cleared (`ProfessionBar.lua:35`).

**C2. Three "what makes this item".** `producerMap` (`Core/UI/ProfessionBar.lua:61-98`: catalog, learned or not,
every realm, cache key misses `Professions:Learned`), `CraftingModel` (`Core/UI/CraftingView.lua:241-279`: learned
only, gathering skipped) and `Crafters.RecipesFor` (`Core/Crafters.lua:220-244`: PB's plus a shipped reverse index built
once). Only the Crafting tab passes producers to Crafting (A1).

**C3. Seven "who can craft it".** `Crafters:WhoKnows` (current market, plus guild; `Core/Crafters.lua:105-204`),
`producerMap` crafters (all realms), `CraftingModel` crafters (all realms, `craftChar` filter), `CraftInstead`'s first
match (`CraftingView.lua:192-201`), live `GetRecipeInfo().learned` (`ProfessionBar.lua:309`, `:328`, `:343`),
`IsPlayerSpell` (Recipes to buy only, `CraftingView.lua:517-519`), Leveling's recorded `learned` and its all-realm
enchanter check (`LevelingView.lua:89`, `:134-136`).

**C4. "Can I learn it", two models.** `Crafting:RecipesToBuy` (`Core/Crafting.lua:257-308`, rank from
`CraftingData:Teaches` with `OVERRIDES`) and Leveling's `learnAt` from raw `CraftingData.data.items`, which skips
`OVERRIDES` (`LevelingView.lua:70-75` vs `Core/CraftingData.lua:84-91`).

### D. Formatting, names and refresh plumbing

**D1. Money helpers.** `local money` in `AHSelling.lua:17`, `AHShopping.lua:28`, `ProfessionBar.lua:372`,
`Tooltip.lua:34` are all `W.Money(c)` (which already rounds and handles nil, `Core/UI/Widgets.lua:562-566`). `signed`
in `ProfessionBar.lua:376` and `Tooltip.lua:38` is `W.SignedMoney` with full money. `LevelingView.lua:32-44` has
`cost`/`gain`/`signed`, exported as `UI.CostText`/`GainText`/`SignedText`, which nothing outside the file uses.
Redundant rounding before `W.Money` at `AHSelling.lua:195`, `AHShopping.lua:369`, `ItemView.lua:1309`, `:1400`. The
"N% cut" text is built by hand six times (`AHSelling.lua:544`, `ArbitrageView.lua:500`, `:502`, `SellAssist.lua:348`,
`ItemView.lua:1377`, `Tooltip.lua:221`). About 14 `"item:" .. id` fallbacks.

**D2. Three item-loading mechanisms.** `ItemCache` events + debounced `OnNamesChanged` (`Core/ItemCache.lua:318-397`);
`W.ItemNameOrLoad`'s own missing list, 0.5 s poll and redraw queue (`Core/UI/Widgets.lua:796-889`);
`DataTable:RenderWhenLoaded` with `W.OnItemLoaded` (`Core/UI/DataTable.lua:494-`). Four views wrap `ItemNameOrLoad`
with their own redraw (`CraftingView.lua:75`, `LevelingView.lua:26`, `MarketOverview.lua:197`, `ProfessionBar.lua:184`).
`ItemCache.Get` has no quality / level / bind / icon, so `Index.lua:95`, `CraftingView.lua:166`, `LevelingView.lua:140`
and `Tooltip.lua:286` call `GetItemInfo` directly.

**D3. No change signal.** `AME:SetIndex` calls `UI:OnIndexReady`, a switch on the current tab
(`Core/UI/Window.lua:449-467`): the profession bar, tooltip caches, AH Shopping and the item page aren't told.
Single-slot `onChange` fields (`Professions.onChange` set at `CraftingView.lua:1042`, `SyncService.onChange`,
`Shopping.onChange` at `AHShopping.lua:560`) mean the last view to assign one wins; the main window uses explicit
`UI:ShoppingChanged` / `UI:WatchChanged` calls instead (~18 call sites). Core pokes UI directly (`Main.lua:253-261`,
`:741`; `Index.lua:36`).

## The core

Five modules, all pure where they can be (game facts come in through small adapters, as `Crafting` already does with
`env`), each with a spec. The UI keeps `W.*` for formatting and DataTable for drawing; it stops computing.

### 1. `Core/Quote.lua`: one price context per auction house

The single answer to "what is this item worth here". It owns the house, cut, deposit, cap, fresh-price overlay and
the derived numbers, and is cached per (shard, index rev, settings generation).

```lua
local q = ns.Quote.For(shard)        -- nil until the shard has an index; ns.Quote.Faction() for your faction's house
q.shard, q.house, q.cut, q.hours, q.index
q:Summary(id)        -- the index summary, or a fresh-search copy (one overlay rule, replaces A6's two)
q:Price(id)          -- market, capped at outlierFactor x avg30 (the one cap: A4)
q:SoldPerDay(id)     -- min(sellRate, qty), nil without a rate (A5; Crafting:SalesPerDay / MarketStats.SoldPerDay)
q:Deposit(id, qty)   -- Arbitrage.Deposit at this house and listing length
q:ListingNet(id, qty)-- SellThrough.Net on the capped price, per unit (A2, A3)
q:BestSale(id)       -- net, "ah" | "vendor" | nil, "unsellable" (Crafting:NetSale's rule, BoP check built in)
q:Worth(id)          -- what one held unit is worth: BestSale's net (portfolio, Sell tab, refine "raw": A8)
q:Disenchant(id)     -- { value, outcomes } with materials at BestSale (A7; one GetItemInfo via ItemCache)
q:CraftEnv(opts)     -- the Crafting env (market, vendorBuy, vendorSell, cut, deposit, sellable, producers, factor)
```

Decisions this fixes:
- **Store the derived per-item numbers in the index at build time** (`BuildIndex`'s `vendorCheck` already writes
  `vendorPrice`, `vendorNet`, `deValue`, `value`): add `soldPerDay` and `net` (one unit, your usual listing length)
  as saved fields and bump `MarketIndex.SAVE_VERSION`. Settings that change them already invalidate the index
  (`Core/UI/SettingsView.lua:278`, `:298`, `:392`). Tables bind columns to those keys, so a sort and a cell can't
  disagree. `sellRate` and `churnRate` stay as they are for `Pricing.Params`, which models demand from them.
- **The house rule is one function** (`Quote.HouseFor(shard)` with the Neutral -> faction fallback), used by A9's
  five sites.
- **The fresh overlay**: an item searched within `Posting.BOOK_AGE` uses its book's cheapest listing for buying and
  `Posting:FreshMarket`'s outlier check for selling. Both live in `q:Summary` and the overlay never mutates the index.
  (A product decision for the user: whether the overlay applies in every view or only Crafting and the post box.
  Recommended: everywhere a single item is priced right after you searched it — Crafting, profession bar, post box —
  and not the screener tables, which stay on the index so they sort consistently.)

### 2. `Core/Holdings.lua`: one answer to "what you have"

Absorbs `Trading.Held`, `Shopping.Progress`'s loop, `Portfolio.Merge`, `heldTotal`, `heldBy`, the two view loops and
`AHSelling.S.ScanBags`'s counting (the Sell tab keeps its live slot list for posting, built on the same walk).

```lua
Holdings.PLACES = { usable = {bags, bank, mail, guild}, carried = {bags}, owned = {bags, bank, mail, guild, auctions} }
Holdings.Count(key, opts)  -- { total, byPlace = {...}, chars = {...}, guilds = {...} }
                           -- opts: places (set or preset), chars ("me" | "market" | "account" | {keys}),
                           --       matchBase (random-suffix keys under their base ID), data (spec injection)
Holdings.Map(opts)         -- { [key] = { qty, chars } } for the whole inventory (Portfolio, refine page, Leveling)
Holdings.Reserve(opts)     -- a stock you draw from: r:Take(key, n) -> taken, from = { {place, char, n} }
Holdings.Shortfall(needs, opts, reserve) -- need - have, one rule (B6)
Holdings.Age(place, char)  -- when a place was last seen (bank, guild, mail are only read when open)
```

Decisions this fixes: the default scope is **your market** (`chars = "market"`), as `Held` does now; "usable"
(bags, bank, mail, guild bank, not the AH) is what shopping, the queue and the profession bar all count, so B2's
overbuy goes away because the list and the queue subtract the same thing. The portfolio uses "owned". One
`BAG_UPDATE_DELAYED` handler (Trading's) fires `HoldingsChanged` (see 5) and the memo is dropped then.

### 3. `Core/Recipes.lua`: one recipe model

Absorbs `PB.Recipe` + `shape`, `recipeFor`, Leveling's candidate shaping, `producerMap`, CraftingModel's producers and
uses, `Crafters.RecipesFor`'s shipped index, and Leveling's raw `teachers` map.

```lua
Recipes.Get(id)              -- { id, profession, product, made, madeMin, madeMax, reagents = {{id, n, alt}},
                             --   cooldown, yellow, grey, src }; live > catalog > shipped, merged per field
                             --   (skill colours from shipped data even when scanned); enchants made = 1, product nil
Recipes.ForProfession(skill) -- catalog and shipped recipes together
Recipes.Teaches(item)        -- { profession, rank, spells } with OVERRIDES; Recipes.TaughtBy(spell) the reverse
Recipes.Producers(item, opts)-- { recipe, crafters } ; opts.learned (only recipes someone knows), gathering skipped
Recipes.Uses(item)           -- recipes that take it as a reagent
Recipes.Knows(charKey, id)   -- recorded learned, plus GetRecipeInfo / IsPlayerSpell for the character you're on
Recipes.Crafters(id, scope)  -- scope "me" | "mine" (your market) | "account" | "network" (with guild, via Crafters)
Recipes.Learnable(charKey, id) -- { known, learnAt, via = "item" | "trainer" | "estimated", ready }
```

One cache, dropped on `TRADE_SKILL_LIST_UPDATE` scans, `Professions:Learned` and the data addon loading (fires
`RecipesChanged`). `Crafters` keeps the sync side (who in the guild knows what) and answers `scope = "network"`.

### 4. `Core/CraftModel.lua`: Crafting's model, built once per change

What `UI:CraftingModel` builds now (`Core/UI/CraftingView.lua:228-307`) moves to core and is shared:

```lua
CraftModel.Get(opts)  -- { quote, craft = Crafting.New(quote:CraftEnv{producers = Recipes.Producers}),
                      --   entries (known recipes, crafters), held = Holdings.Map{places = "usable"} }
                      -- memoised on (index rev, holdings gen, recipes gen, char filter)
CraftModel.Evaluate(recipeID) -- the one Crafting:Evaluate for a recipe: Crafting tab rows, profession bar, tooltip
CraftModel.Instead(itemID)    -- CraftInstead (Sell tab, item page)
```

`Crafting.lua` itself stays as the pure maths; it loses `SalesPerDay` and `Price` to `Quote` (kept as one-line
delegates while specs call them, then removed).

### 5. `Core/Events.lua`: one change signal

A tiny bus (`Events.On(name, fn)`, `Events.Fire(name, ...)`, coalesced to once a frame) with these names:
`IndexReady(shard)`, `HoldingsChanged`, `RecipesChanged`, `NamesChanged`, `ShoppingChanged(list)`, `WatchChanged`,
`SyncChanged`, `SettingsChanged(key)`. Core fires; views subscribe in their `Create*View` and redraw when shown. It
replaces `UI:OnIndexReady`'s switch, the single-slot `onChange` fields, the direct `ns.UI:Refresh*` pokes from Core,
and the extra `BAG_UPDATE_DELAYED` frames.

### UI side (not a core module, but the same rule)

- `W.Money(v)` everywhere (local wrappers deleted); `W.SignedMoney(v, { full = true, zero = "0" })` covers
  ProfessionBar's, Tooltip's and LevelingView's `signed`/`cost`/`gain`; `W.CutText(cut)` for "5% cut";
  `W.ItemLabel(key)` for name-or-`item:id`.
- `ItemCache.Get` gains `quality`, `level`, `bind`, `icon`; `W.ItemNameOrLoad` and `DataTable:RenderWhenLoaded` sit on
  `ItemCache` + `Events "NamesChanged"` instead of their own polling.

## What each view reads instead

| View | Today computes | Reads instead |
|---|---|---|
| MarketView | raw `sellRate` column | `s.soldPerDay`, `s.net` (index fields) |
| ItemView | net after cut (`:1373-1375`), raw rate, `market/avg` | `q:ListingNet`, `s.soldPerDay`; `CraftModel.Instead` |
| Tooltip | its own Crafting env, cut, DE value, house nets, rate format, `Held` | `CraftModel.Evaluate`, `q:Disenchant`, `q:ListingNet` per house, `W.Rate`, `Holdings.Count{places="owned"}` |
| AHSelling (Sell tab) | `S.Worth`, `cut()`, own bag walk | `q:Worth` / `q:BestSale`, `Holdings` walk |
| SellAssist | `Sell.Net` | `q:ListingNet` (house from `Quote.HouseFor`) |
| ArbitrageView | deposit per unit, net, re-sort | `Arbitrage.Find(buyQuote, sellQuote, opts)` returns `deposit`, `net`, sorts by either |
| PortfolioView | gross worth, raw days-to-sell | `Portfolio.Build(Holdings.Map{places="owned"}, basis, quote)` using `q:Worth`, `q:SoldPerDay` |
| MarketOverview | (MarketStats, already core) | `q:SoldPerDay` / `q:Price` inside MarketStats |
| CraftingView | `CraftingEnv`, `recipeFor`, model, held loop | `CraftModel.Get`, `Recipes` |
| ProfessionBar | `PB.Craft`, `PB.Recipe`, `producerMap`, `heldTotal`, `PB.Summary` shortfall | `CraftModel.Evaluate`, `Recipes`, `Holdings.Shortfall` with the queue's reserve |
| LevelingView | candidate shaping, teachers map, held loop, deValue | `Recipes.ForProfession` / `Learnable`, `Holdings.Map{chars={key}}`, `q:Disenchant` |
| ShoppingView / AHShopping / VendorPanel | `Shopping.Progress` holdings loop, missing walk | `Holdings.Shortfall` (Progress takes it as a parameter) |
| CraftersView | (Crafters, already core) | `Recipes.Crafters(id, "network")` |

## Migration order

Every step is one commit, ends with `busted` (541 specs), `luacheck Core spec`, `stylua` and
`lua5.1 scripts/locale-keys.lua` passing, and ships nothing half-moved: a new module goes in with its spec, callers
switch, then the old copy is deleted in the same or the next step. Steps 1-7 are **behaviour-preserving** (no spec
expectation changes; if one has to change, the step is wrong). Steps 8-12 **change numbers on purpose**; each names
the specs whose expectations move, and those are updated in the same commit with the reason in the message.

1. **Formatting.** `W.SignedMoney` options, `W.CutText`, `W.ItemLabel`; delete local `money` / `signed` and the
   unused `UI.CostText` exports. Specs: `widgets_spec` gains cases. (~-45 lines)
2. **Events bus.** `Core/Events.lua` + spec; `SetIndex` fires `IndexReady`, `UI:OnIndexReady` becomes a subscriber
   per view; replace `Professions.onChange` / `Shopping.onChange` / `SyncService.onChange` with events; keep
   `UI:ShoppingChanged` as a thin `Fire` until its callers move. Integration specs that drive `OnIndexReady` still pass
   because the subscribers do the same refreshes. (~-15 net)
3. **ItemCache facts.** `quality`, `level`, `bind`, `icon` in `ItemCache.Get`; the four direct `GetItemInfo` callers use
   it; `ItemNameOrLoad` / `RenderWhenLoaded` on `NamesChanged`. Specs: `itemcache_spec` gains cases; `helpers/wow.lua`
   may need the extra `GetItemInfo` returns. (~-70)
4. **`Quote` with today's rules.** `Quote.For` / `HouseFor`, `Price`, `SoldPerDay`, `Deposit`, `BestSale` (= today's
   `Crafting:NetSale`), `CraftEnv` reproducing `UI:CraftingEnv` exactly (fresh overlay included). `UI:CraftingEnv`
   becomes `Quote.Faction():CraftEnv(...)`; `Crafting:SalesPerDay` / `Price` and `MarketStats.SoldPerDay` delegate.
   Specs: new `quote_spec`; `crafting_spec`, `market_stats_spec` unchanged. (~-40)
5. **`Recipes`.** `Recipes.Get` returning exactly what `recipeFor` returns today (catalog first), `Producers`,
   `Uses`, `Teaches`; `recipeFor` and CraftingModel's producer loop call it. `PB.Recipe` keeps its live-first order
   via `Recipes.Get(id, { live = true })` for now. Specs: new `recipes_spec`; `professions_spec`,
   `crafting_data_spec` unchanged. (~-60)
6. **`Holdings` with today's scopes.** `Holdings.Count` / `Map` / `Reserve` with explicit `places` and `chars`; each
   caller passes the scope it uses now (Progress: bags+bank, account; Held: all five, market; ...), so nothing moves
   yet. `Trading.Held` and `Portfolio.Merge` delegate. Specs: new `holdings_spec`; `trading_spec`, `shopping_spec`,
   `portfolio_spec`, `craftqueue_spec` unchanged. (~-50)
7. **`CraftModel`.** Move `UI:CraftingModel` / `CraftInstead` to core on `Quote` + `Recipes` + `Holdings`. Integration
   specs on `UI:CraftInstead` keep passing through a one-line `UI.CraftInstead = CraftModel.Instead`. (~-30)

   From here, numbers change.

8. **One Crafting env.** `PB.Craft` and `Tooltip.RecipeLines` use `CraftModel`: producers, `sellable` and the fresh
   overlay everywhere; Tooltip's hand-rolled cut goes. Moves: `integration_spec` profession bar / RecipeLines
   expectations where a part is now crafted or a product is BoP. (~-45)
9. **One recipe order.** `Recipes.Get` becomes live > catalog > shipped, merged per field; `PB.Recipe`, Leveling
   candidates and the tooltip use it; shipped fallback for the queue; cooldowns everywhere; Leveling uses
   `Recipes.Learnable` (OVERRIDES applied); enchant `made` normalised. Moves: `leveling_spec`, `craftqueue_spec`
   (a queued unscanned recipe now plans), `integration_spec` bar cases. (~-80)
10. **One "usable" holdings scope.** Shopping, the queue, the profession bar, Crafting and Leveling count
    `places = "usable"`, `chars = "market"`; `QueueToShopping` sets the shortfall and Progress subtracts the same
    places (B2 fixed); `PB.Summary` draws from the queue's `Reserve`. Portfolio uses "owned". Moves: `shopping_spec`,
    `craftqueue_spec`, `vendorpanel_spec`, `portfolio_spec` (market scope). (~-40)
11. **Derived fields in the index.** `soldPerDay` and `net` written at build, `SAVE_VERSION` 7; every Sales/day column,
    the tooltip and the item page read `soldPerDay`; Sell tab, refine "raw", ItemView/SellAssist nets and the per-house
    tooltip rows read `q:ListingNet` / `q:Worth`; DE values all from `q:Disenchant`; Portfolio worth after the cut;
    `Arbitrage.Find` takes quotes (capped sell price, deposit and net inside). Moves: `market_index_spec` (fields,
    version), `portfolio_spec`, `arbitrage_spec`, `tooltip_spec`, `integration_spec` value checks. Help texts and
    locale keys for "Sales/day" may need a word (run `locale-keys.lua`). (~-60)
12. **Cleanup.** Delete the delegates (`Crafting:SalesPerDay`/`Price`, `MarketStats.SoldPerDay`, `Trading.Held`'s
    body, `Portfolio.Merge`, `UI:CraftingEnv`, `PB.Recipe`, `producerMap`, `recipeFor`), move specs that still call
    them to the new modules, and add a `spec/toolchain_spec.lua` guard: no `Settings:AuctionCut`, `Arbitrage.Deposit`
    or `C_Item.GetItemInfo` under `Core/UI/` (the rule that keeps this from growing back). (~-60)

Steps 1-3 are independent of each other; 4-6 are independent of each other once 2 is in; 7 needs 4-6; 8-11 need 7 and
are otherwise independent (11 is the largest and can split by view). Each of 8-11 is one visible change worth a
changelog line and a quick in-game check of the views it names.

## Estimated code removed

Rough, from the sizes of the copies above (gross removed from views and duplicated core code / added in new modules):

| Area | Removed | Added | Net |
|---|---|---|---|
| Crafting envs, house / cut / deposit / net copies, fresh overlays, DE values (A) | ~260 | ~140 (`Quote`) | ~-120 |
| Holdings loops, shortfalls, bag walk, extra event frames (B) | ~190 | ~120 (`Holdings`) | ~-70 |
| Recipe shaping, producer maps, crafter sets, teachers map (C) | ~230 | ~150 (`Recipes`, `CraftModel`) | ~-80 |
| Money / sign / cut / label helpers, item loading, refresh switch (D) | ~200 | ~60 (`Events`, Widgets options) | ~-140 |
| **Total** | **~880** | **~470** | **~-410** |

Specs grow (five new spec files, roughly +300 lines) while the UI files shrink; the bigger gain is that A1-A9, B1-B6
and C1-C4 can no longer happen, since there is one place each number comes from.

## Out of scope

- The pricing model (`Pricing.lua`) and sell-through maths stay as they are; they're already single sources.
- Sync, Store, history and the index build pipeline aren't touched beyond the two saved fields in step 11.
- A warband / account bank in `Holdings` waits on confirming Forever has one (B5).
