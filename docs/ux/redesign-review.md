# Redesign review (Nov 2026)

What to change so AME works as one tool for selling, buying, crafting and sharing, not a set of pages. It builds on
[user-stories.md](user-stories.md) and [feature-map.md](feature-map.md). Nothing here is fixed: layout, navigation and
the look are all open.

## What we found

1. **AME is organised by data, players think in situations.** The tabs are Market, Arbitrage, Portfolio, Crafting, Item
   and Guide. A player is *at the AH selling*, *out farming* or *looking for a crafter*. Each situation needs pieces from
   three or four tabs, and the pieces don't link up: the Item page can't search the AH, "make it first" can't queue the
   craft, a crafted item can't be posted, a crafter can't be sent the mats.
2. **The same thing exists twice, done differently.**

   | Duplicate | Copies |
   |---|---|
   | Crafter finders | Find a crafter (page) and Who can make it (popup), plus "Made by" (tooltip) and "Network" (column) |
   | Selling UIs | The Selling tab and the sell bar |
   | Shopping-list behaviours | Four of them |
   | Net prices | Three calculations |
   | Sync status | Four places |
   | Posting advice | Three shapes |

3. **Words drift.**

   | Concept | Names in use |
   |---|---|
   | Sells per day | 5 spellings |
   | Crafting before selling | Arbitrate, Arb, refine, "Better: make", "Make it first" (and Arbitrage means something else) |
   | Units on sale at a price | Units, Depth |
   | All your characters | Account, All characters |
   | Sharing | share, sync, sharing |

4. **Clicks mean different things.**
   - Row click opens the Item page, except in Arbitrage and Crafting, where it selects.
   - Shift-click searches the AH in two tabs and links to chat elsewhere.
   - Right-click removes, selects or opens a menu, depending on the list.
   - There is no back button, and Escape closes everything.
5. **One house picker, many houses.** The title bar's AH picker changes Market and Item only. Tooltips, Portfolio,
   Crafting, lists and alerts use your faction's AH, and Arbitrage has its own pair. One screen can show two prices for
   the same item.
6. **Daily routines are slow against TSM and Auctionator.**
   - Posting: one item per click.
   - Undercuts: no cancel scan.
   - Buying: two clicks per buy, and you move to the next item by hand.
   - Mailbox and vendors: no open-all mail, no vendor selling.
   - No key bindings.
   - AME's AH tabs disappear when Auctionator is installed, so a switching player never sees them.
7. **Social crafting stops at a whisper with a link.** There are no requests, no mats or tip, no offers and no tracking.
8. **Important pages are buried.**
   - Off by default: Market overview and the chart click.
   - Sync activity sits inside Settings.
   - Alerts have no list.
   - Some actions exist only as slash commands.
9. **The Guide disagrees with the code in about 15 places** (listed in the inventories): commands that don't link, wrong
   button names, a setting that doesn't exist, a sort order that isn't the default, and the bell's position.

## Decisions so far (2026-11-23)

- **Scope:** AME doesn't take over the mailbox (other addons do that well): WEALTH-3 and WEALTH-4 are out. Cancelling
  auctions stays the game's job; AME flags undercut auctions (SELL-6) but adds no cancel scan.
- **The AME window takes over the auction house** (accepted, see 5): at the AH it switches to Buy, Sell and Auctions
  modes, and the game's AH frame stays open underneath, hidden.
- **Auctionator stays a choice, through one switch, not a setting.** AME began as Auctionator's sidecar.
  - Without Auctionator, AME takes over.
  - With Auctionator, the game's AH (and Auctionator in it) shows as today, with AME's sell bar, tooltips and window.
  - Either way, one button swaps: "Use the game's AH" in AME's takeover, and "Open in AME" on the game's AH frame.
    The last choice is remembered.
  - No mode shows both at once.
- **Interaction contract** (direction 1): accepted.
- **Tab set** (direction 2): Home, Market, Item, Crafting, Guild, Portfolio, Guide, with Settings behind the cog -
  accepted.
- **Shift-click depends on where you click:**
  - Inside AME: the game's meaning (link to chat while a chat box is open); searching the AH is a button.
  - In bags, the bank or on a chat link, while no chat box is open: look the item up in AME (its Item page; at the
    AH, its listings too).
  - While you're writing a chat message, Shift-click always links, everywhere.
  - To check in game: Shift-click on a stack in the bags also opens the game's split-stack box.
- **Craft requests** between AME users (direction 7): wanted, to be designed.
- **The Guild tab is `social` in code.** Module, setting keys and the slash word use `social`; the locale strings say
  "Guild".
- **Crafting has two modes, as the auction house has** (decided 2026-11-23). AME takes over: opening a profession
  opens the Crafting tab, which is the recipe list and creates (Create, Create all, Queue), with a way back to the
  game's window. Beside the game's window: the game's window stays the recipe list with AME's bar under it, and the
  Crafting tab is the view across characters (All professions, Ready now, To learn). One setting: "Opening a
  profession". Sections, their order and skill-up marks come from the game (`C_TradeSkillUI.GetCategoryInfo`: name,
  uiOrder, parentCategoryID; confirmed in the Forever client), stored per recipe when a character opens the profession.
  Takeover has no Track Recipe: the game's Track pins a recipe to the quest tracker, and the queue fills that role.
  The sidecar stays as an option (decided 2026-11-24): with "Opening a profession" set to the game's window, AME
  adds one frame beside it, not the AME window. The frame holds what the bar under the window held (the picked
  recipe's cost, sells for, profit, Make N, Queue) and then the queue; the bar under the window goes. Profit per
  recipe stays in the game's list. "Open in AME" on the frame swaps to takeover, which is the default.
  The queue shows in the game's objectives tracker (decided 2026-11-24): out in the world the AME window is closed,
  so the queue's missing reagents show in the tracker and count up as you gather. A setting, on by default, in both
  modes. To check in game: whether `C_TradeSkillUI.SetRecipeTracked` is enough (it shows one craft's reagents per
  recipe, not the queued count, and only for recipes this character knows) or AME needs its own tracker block.
- **Crafting is one screen, laid out as the game's window** (to confirm on the sketch): a profession picked on the
  left, its recipes in the game's foldable sections with the skill-up colour, a Ready column and filters; folds,
  filters and search are remembered. "All professions" is the flat view. It replaces Top earners, Sell or refine,
  Recipes to buy and the Craft queue page. Leveling and Your professions stay as pages. It must match or beat the
  game's own window (`reports/Crafting UI pain points and wishes.md`).
- **Lists is a mode of Market** (to try): Screener · Overview · Arbitrage · Lists.
- **Item at the auction house** is the Item page plus one Buy card; selling is only under Sell.
- **At the auction house** Buy / Sell / Auctions hang under the window, and the window opens where you last were at
  the AH.
- **No retrofit of the old boards.** The current boards get no theme switch, no side-by-side and no board-by-board
  comparison with the game: they're replaced as each screen is redesigned. New boards carry the faction theme switch
  from the start (canvas page "Redesign"), and one colour set in the repo will feed both the game and the canvas.
- **The look: hybrid.** Flat dark content for tables and charts, game-flavoured chrome (bronze frame, gold headings in
  the game's font, gilt primary buttons).
- **Two colours in the chrome.** "Azeroth" in the title is always in your own faction's colour; the accent (the title
  bar's edge, the active tab, primary buttons, the picked row) follows the market you're viewing. A Horde player on
  the goblin AH sees a red "Azeroth" with a gold accent; an Alliance player at home sees both in blue.
- **One colour set:** `docs/ux/design/tokens.lua`. `scripts/design-tokens.lua` writes `tokens.css` from it for the
  canvas, and `ame.css` is the shared look every new board links. The addon's palette moves to it screen by screen.
- **R0** (fix now): done.

## Fix now (bugs, no design needed) - done

| Issue | Where | Story |
|---|---|---|
| Buy confirms whichever purchase is pending, not the item on screen | `Core/UI/AHShopping.lua:552` | BUY-3 |
| No Cancel for a pending purchase (`AHSearch:Cancel` is never called) | AHShopping | BUY-3 |
| Search all is cancelled silently by any other search | `Core/AHSearch.lua:148` | BUY-1 |
| Only the 5 cheapest gear listings can be bought | `AHShopping.lua:812` | BUY-7 |
| Searching a guild list from Market searches only its first item | `Core/UI/ShoppingView.lua:265` | BUY-1 |
| `/ame scan`, `/ame who` aren't command links in the Guide | `Core/UI/Help.lua:635` | LEARN-4 |
| `marketDay` missing from the glossary (right-click lands on Getting started) | Help.lua | LEARN-2 |
| Guide mismatches: "With Crafting on", "ranked by Market/day", "Add reagents", bell position, 7-day average claim, sidebar short count, top-price count | Help.lua | LEARN-4 |
| Dead `crafting` setting | `Core/Settings.lua:31` | — |
| "+N older" notifications can't be opened | `Core/UI/Notices.lua` | ITEM-8 |

## Proposed direction

### 1. One interaction contract, everywhere

- **Click** an item row: open it in the Item page. Pages where a row has its own detail (Arbitrage, Crafting) show that
  detail in the sidebar, and the sidebar's item link opens the Item page. The rule is written down and the same on
  every page.
- **Shift-click** inside AME links in chat (the game's meaning); in bags, the bank or on a chat link, with no chat
  box open, it looks the item up in AME. **Ctrl-click**: dressing room. Searching the AH becomes a visible button, not
  a modifier.
- **Right-click** an item, anywhere, opens the one item menu. Right-click a list opens the list menu.
- **Back / forward** in the title bar, with a history of pages and items. Escape steps back, then closes.
- **One market at a time.** The house picker sets the market for every number in the window (Arbitrage keeps its own
  pair, since comparing two houses is its point). Tooltips say which house they show.

### 2. Navigation by situation

Tabs (accepted):

| Tab | Holds | Replaces |
|---|---|---|
| **Home** | What to do now: fired alerts, undercut auctions, cooldowns ready, craft requests, top opportunities for *your* professions and bags, sync health | (new: GOLD-7) |
| **Market** | Screener · Overview · Arbitrage (modes of one page) | Market, Arbitrage |
| **Item** | The hub for one item, with actions (see 3) | Item |
| **Crafting** | Professions · Queue · Top earners · Sell or refine · Recipes to buy · Leveling | Crafting minus Find a crafter |
| **Guild** | Crafters directory (one, merged) · Requests · Guild lists · Sharing activity and peers | Find a crafter, Who can make it popup, Settings > Sharing (the dashboard part) |
| **Portfolio** | Positions · Auctions (with undercuts) · Ledger · Customers | Portfolio |
| **Guide** | As now, with links into the pages it describes | Guide |

Settings stays behind the cog. Each page gets a small "settings for this" link that opens the matching section.

### 3. The Item page as a hub

- **Action bar:** Search the AH · Add to list · Post (at the AH) · Watch · Alert · Who can make it · Make it (when yours
  can).
- **Cards:** your position (held where, average cost, unrealised), other houses, made from / used in / made by, and the
  posting ladder with a quantity.

### 4. One component per job

- **Crafter finder:** one component. The Guild page shows it in full; the item menu opens it filtered to that item;
  the tooltip's "Made by" names lead to it.
- **Price ladder:** one, used by the Selling tab, the sell bar and the Item page, with the same wording and order.
- **Reagents to a list:** one action. It always asks which list (the last one used comes first) and how many crafts,
  and it always adds.
- **Net:** one definition (after the cut, and the deposit weighted by the chance it doesn't sell), named the same
  everywhere.

### 5. AH workspace (the Switcher's daily routine)

At the AH the AME window takes over: the game's frame stays open underneath (closing it would end the AH session) but
hidden, and the window switches to the modes below. A button swaps back to the game's AH (and Auctionator, if it's
installed), and the game's frame gets an "Open in AME" button to swap again. AME starts in takeover without Auctionator
and in the game's AH with it, then remembers the last choice. This replaces today's Shopping and Selling tabs inside the
game's frame; the sell bar stays for the game's and Auctionator's sell windows.

| Workspace part | Routine | Stories |
|---|---|---|
| **Sell** | A post queue: everything in the bags (or a saved group) at the suggested price, one key posts and moves on; prices and durations remembered per item | SELL-3, SELL-7 |
| **Auctions** | Your auctions with an undercut flag, and a repost through Sell once the game's window has cancelled them | SELL-6 |
| **Buy** | A buy loop over a list: one key buys up to the need at or under the top price, then moves on; safe confirm; all listings | BUY-1, BUY-3, BUY-4, BUY-7 |
| **Key bindings** | For the loops, opening AME and scanning | LEARN-5 |

### 6. Out in the world and at vendors

- **Vendor:** "Sell junk and vendor-tip items" next to the merchant frame, with a preview and buyback (FARM-5).
- **Session tracker:** bag value now, gold made this session, per hour; a small optional HUD (FARM-2).
- **"Worth farming"** as a screener view: gatherable mats ranked by price × sell rate (FARM-3).

### 7. Social crafting

- **Request:** pick a crafter, and AME writes the whisper with the item, the mats you bring (or a mats-provided
  toggle) and a suggested tip, computed from the product's price minus the mats. The request is tracked under Guild >
  Requests; with AME on both sides it arrives as a request, not just a whisper (ASK-2…6).
- **Offer:** a crafter marks recipes "taking orders" and can post a short advert with links to trade or guild chat
  (HELP-2, HELP-3, HELP-6).
- **Requests that do not need both players online (the author's idea, 2026-11-24; proposed, not yet drawn):**
  - *Carried by the guild.* A request to an offline crafter is stored and passed on by guild members' AME (the sync
    mesh), so it arrives when the crafter next logs in, through one or more relays. It carries an id, an expiry, and
    a withdrawn/declined marker so old copies die out.
  - *The crafter answers.* Accept as asked, answer with a price or fee (the asker then agrees or withdraws), decline,
    or just whisper the asker.
  - *Mats by mail.* The asker can choose to supply the mats. At a mailbox AME prepares the mail (crafter, subject,
    body, the mats attached) and the player sends it; AME does not take over the mailbox.
  - *The mail is the fallback.* Its body is the request in plain words, and its subject carries the request id, so
    the crafter's AME picks the request up from the inbox if no relay reached them, and a crafter without AME can
    read it. The mail and the relayed copy are matched by id.
  - *Possible follow-on:* the crafter mails the products back, with the fee as cash on delivery; "handed over" is
    then set by the mail as well as by a trade.
  - To check in game: sending prepared mail from addon code on one click; reading a mail body marks it read (so the
    id sits in the subject); mail delay between characters on Forever; attachments per mail.
- **Enchanters:** the DE and enchant signals lead to the Guild crafters directory filtered to Enchanting (HELP-5).

### 8. Words

One glossary of UI terms, enforced by a spec on the enUS locale:

| Use | Instead of |
|---|---|
| Sells/day | Sells per day, Sales per day, sold/day |
| Market/day | Market a day |
| Make it first (tip: **Craft**) | Arbitrate, Arb, refine, Better: make |
| Lowest listing | Lowest, Cheapest, Low |
| Units | Depth |
| All characters | Account |
| Sharing (the feature), sync (the transfer) | share/sync used for both |
| Search the AH | Search AH, Search |

## The design canvas

The canvas is more wireframe than the game in places and more polished in others. Plan:

1. **One source of colours.**
   - Replace the ~30 hard-coded hex colours on the canvas with named tokens, taken from `Core/UI/Widgets.lua`
     (`W.COLORS`, `W.THEMES`, the selected, primary and tag shades).
   - Generate the canvas tokens from the Lua with a script, so the two can't drift.
2. **Faction themes on the canvas.**
   - Each screen board gets a theme switch (Horde red, Alliance blue, Goblin gold).
   - The accent and its derived shades follow the switch, using the same maths as `W.PrimaryShade` and the selected
     tint.
   - One board shows the same screen in all three themes side by side.
3. **Parity pass.**
   - For each board, compare against an in-game screenshot.
   - Where the canvas is more polished, the game is brought up to it; where the game is ahead, the board is updated.
   - The canvas then leads, as the design-first rule says.
4. **Then the redesign** on the canvas, in the order below, before any code.

## Order of work

| Step | What | Size |
|---|---|---|
| R0 | Fix-now list above | small |
| R1 | Pick the look (three Home boards); one colour set in the repo for the game and the canvas | done |
| R2 | Interaction contract, back/forward, one market, words | medium |
| R3 | Navigation (Home, Guild) and the Item hub, on the canvas first | large |
| R4 | AH workspace: post queue, auctions/cancel, buy loop, beside Auctionator, key bindings | large |
| R5 | Social crafting: requests, offers, tips | large |
| R6 | Farming, vendor selling, session tracker | medium |

The redesign itself (R1 onward on the canvas) runs on Claude Fable.

### How the screens are built: layouts as data, drawn by widgets (decided 2026-11-24)

For the whole addon, following the author's own `@evanion/widget` (https://libs.evanion.com/rendering/):

- A screen is a tree of items: `{ id, type, props, meta, children }`. `type` names a widget, `props` is the widget's
  data, `meta` is placement and belongs to the layout (a widget draws the same wherever it sits), and a shared context
  carries what every widget needs (the market, the character, the theme).
- One registry maps a type to the widget that draws it. The widget set is the canvas's component set: TitleBar,
  Sidebar, DataTable, Card, SettingsCard, Segmented, Button, Input, ItemLink, Money, StatusBar.
- Behaviour stays in code: the layout holds no conditions, bindings or handlers. A view's code builds the item tree
  from its state and hands it to the renderer.
- A validator returns a list of problems and never errors (unknown type, missing prop, duplicate id). It runs in the
  specs over every screen's layout. The renderer is tolerant: it skips an unknown type and warns once.
- Takeover and sidecar frames are the same widgets in a different layout, which is why Crafting can offer both.

The architecture is adapted to Lua and the game's UI, not copied from the web (confirmed 2026-11-24):

| On the web | In the game |
|---|---|
| A widget is a function that returns elements; the tree is redrawn | A widget has two halves: create its frames once, then update them from `props` any number of times |
| Elements come and go | Frames are never freed: the renderer keeps one frame per `id`, hides what the layout drops, and pools repeated types |
| CSS lays items out from `meta` | A few layout widgets (row, column, grid, fill) read `meta` and set the anchors; sizes are explicit |
| TypeScript checks props | Each widget declares its props; the validator checks layouts in the specs, and at load in a debug mode |
| Handlers are passed as functions | The layout names an action (`action = "queue"`); the view owns the handler. Layouts stay plain data, so a spec can read them and they could be saved |
| A list is many items | DataTable (and the chart) is one widget fed by a data source: it draws its visible rows and never puts rows in the tree |

Rules the game adds: a click that crafts, posts or buys must reach the game from the real button press, so those
widgets call their action directly from the click; text is localised by the view before it reaches `props`; and a
view updates `props` in place, without building a new tree on each event, to keep garbage down during scans.

Lists is a mode of Market (confirmed 2026-11-24): a list is the Market table narrowed to a set of items, with
quantities and a top price when it is a shopping list.

The old Crafting boards are retired from the canvas (2026-11-24), after their details were carried to the one
screen: Top earners' Tools section is on the new Missing something board (the tool a recipe needs and how to get
one); the Craft queue page is the new Queued board (steps, make or buy, where each material comes from, To do);
Sell or refine's in-and-out craft card is on Ready now; Recipes to buy is To learn; the Who can make it popup is
Guild · Crafters. CraftingNav and CraftingToolbar stay until Leveling, Your professions and Guild · Crafters are
redrawn without them.

Where a tool comes from is in its tooltip (decided 2026-11-24): the Tools section shows the tool as an item link,
whether one of your characters has it, and one short line; "Made by Engineers (250)", "Sold by ...", the schematic
and the price are lines AME adds to the item's tooltip, so they show wherever the item is linked. No button for it.
A tool that is a place (Forge, Anvil, Cooking Fire) is not an item: it shows as plain text in the game's words, with
whether the character is near one, and has no link or tooltip. Forever also has camp deployables (two or three per profession): items you make with a profession recipe or
buy from a crafter or the auction house, and deploy at a camp. Most only add a camp buff or a utility (Alchemy's
Fermenter, Leatherworking's Tanning Rack, Engineering's Repair Bot); some serve crafting (Tailoring's Loom unlocks
high-level crafting; Blacksmithing's Anvil; Cooking's Campfire). So AME treats them two ways. As products, every
deployable is a recipe with a cost and a price like any other. As tools, only the ones a recipe requires show in
the Tools section, read from the game's requirements and never from a list of ours: an item link, with whether
one stands at this camp, one of yours holds one, or neither. Blizzard may later make deployables spells or toys;
then the name stays and the link goes. Drawn as a row on Missing something (a Loom). The list above is from
guides the author passed on, not checked in game. Early deployable blueprints drop from low-level dungeon bosses (Anvil: Gilnid, The
Deadmines; Fermenter: Rath'mael, Ruins of Lordaeron; and so on), so To learn needs a third source beside the auction
house and vendors: "blueprint drops: boss, dungeon". AME cannot read drop sources from the game; this would be a
small table kept by hand, for deployable blueprints only. At least some blueprints can be traded, so they also sell on the auction house: a blueprint AME has seen listed
shows as any recipe does (price, payback, Buy), and the drop line is the fallback when none is listed. AME learns
which blueprints trade from seeing them on the auction house, not from a list. 

Where drop sources come from (researched 2026-11-24, a quick pass): no maintained library fits. LibPeriodicTable
has instance loot under a compatible licence but is retail-only and stale since 2023; the AtlasLoot forks, one of
which covers Forever, are GPLv2 static tables that an LGPL addon cannot copy. The plan, in order: (1) the game's
Encounter Journal (`EJ_SelectInstance`, `C_EncounterJournal.GetLootInfoByIndex`), which the API wiki lists for
Forever 1.60.1, read once into a cache with the loot filters reset; unconfirmed is whether Forever's journal is
filled in and lists recipe items. (2) A small hand-kept table for what the journal omits, as `Core/Disenchant.lua`
is. (3) Optionally, the boss recorded when a player loots one (`ENCOUNTER_LOOT_RECEIVED`), shared over guild sync.

Drop sources are for every recipe, not only deployable blueprints (decided 2026-11-24): one "Where from" for all
of To learn, filled from whatever source knows. That rules out a hand-kept table as the main source: classic-era
recipes drop from bosses, named mobs, zones and the world, come from quests and reputation vendors, and number in
the hundreds; mob loot tables are on the server and not in the client's data. So the sources, in the order tried:
seen on the auction house or at a vendor (AME's own data); the Encounter Journal (bosses only); a loot addon the
player has installed, asked at runtime (AtlasLoot has a Forever fork; reading its data in game copies nothing, as
with Auctionator); drops recorded by you and your guild; and otherwise "source not known", never a guess. A hand
table stays only for gaps that matter and that nothing else covers.

Parked (2026-11-24): drop sources on recipes are left out for now. To learn keeps the sources AME already has
(the auction house, vendors, trainers); the notes above stand for when it is picked up again.

A possible next project (the author's idea, 2026-11-24): a library for item sources, as LibAMEChart is for charts.
To keep that open, AME's source lookup is written as one module with providers behind one question ("where does
this item come from"), with no AME types in its interface, so it can be lifted out later.
To check in game: that the recipe's requirements say
which are items and which are met (`C_TradeSkillUI.GetRecipeRequirements`).

Named actions are decided (2026-11-24), in the Flux manner the author knows from Redux: a widget dispatches a named
action with a small payload, the view handles it and changes state, and the changed state flows back as `props`.
Widgets never change state themselves. Protected clicks may sidestep this: where the game needs the call made
straight from the button press (crafting, posting, buying, or a secure button), the widget makes the call itself
and then dispatches the action to report it.

To settle when the first screen is built: whether the game's ScrollBox drives the DataTable, and the measurement
(in `bench/`) of a screen built this way against the hand-placed one.

## Questions to settle before R3

None open: see Decisions so far.

## Progress on the canvas

Canvas pages: **Existing screens** (every current screen, re-skinned, some redesigned in place) and **New screens**.

| Screen | State | What changed |
|---|---|---|
| All existing screens | re-skinned | The hybrid look, the shared colour set, square corners, the new title bar and tab row, theme and faction switches |
| Home | new | What to do now, and what's worth doing today |
| Market | redesigned | Three modes (Screener, Overview, Arbitrage); "Your alerts" in the sidebar; a "You hold" column; the row-click rule under the table |
| Market, Arbitrage mode | redesigned | A mode of Market; star column; "Add to a shopping list" and "Open item" next to Search; "Sells/day there" and "Units" in the route's data |
| Item | redesigned | An action bar (Search the AH, Post, Add to a shopping list, Watching, Alert, Who can make it, Hide); under the chart: Your position, Other auction houses, Crafting; a Verdict card; the posting ladder takes what you hold |
| At the auction house: Market | new | The same screener, searching the AH live: what's on sale now beside AME's market view; shopping lists in the sidebar |
| At the auction house: Market, a shopping list | new | The list against what's on sale now, Search all, and buying down the list (Confirm, Skip, Cancel), capped at your top prices |
| At the auction house: Item, narrow | new | Chart, On sale now and Sell yours take turns; the title bar folds the scan and the swap into one AH menu |
| At the auction house: Market and Portfolio > Sell, narrow | new | The narrow-window versions: the search and results; the bags beside the posting form |
| At the auction house: Item | new | The chart, what's on sale now with Buy / Confirm / Cancel, and Sell yours with the one price ladder |
| At the auction house: Portfolio > Sell | new | Your bags by worth, the price ladder, the item's chart and listings, Post and next |
| At the auction house: Portfolio > Auctions | new | Your auctions against what's on sale now, Check prices, Cancel per auction |
| The game's AH window | redesigned | An "Open in AME" button; the sell bar shows the same four-step ladder |
| Portfolio | redesigned | A Where column, "All characters", the undercut count, the click rule |
| Session tracker | new | A small panel for farming: what the outing is worth, the rate an hour, the best finds |
| Guild: Crafters | redesigned | Was Crafting > Find a crafter and the Who can make it popup: one finder, with Ask writing the request (mats, suggested tip) |
| Guild: Requests | new | Asked of you and what you asked; mats, what the craft is worth, Accept / Decline |
| Guild: Your crafts | new | The offering side: taking orders per profession, what guildmates look up, your tip per craft, an advert for chat |
| Guild: Guild lists | new | The shared watchlists and shopping lists: read, copy, search |
| Vendor: sell | new | Beside the merchant window: sell what AME tips Vendor, and junk, in one go |
| Guild: Sharing prices | moved | Was Settings > Sharing; same content under the Guild tab |
| Settings, General | redesigned | "At the auction house" (AME's window or the game's); Fonts and bars (LibSharedMedia); the Market overview switch and the Sharing section are gone |
| Crafting, Recipes to buy | redesigned | "Guild crafters" (was Network), a From column, recipes a vendor sells |
| Crafting, Sell or refine | redesigned | "Sell it raw" and "Open item" next to queueing |
| Crafting, Leveling | redesigned | "Reagents and recipes to a list": the recipes to learn go on the list too |
| Crafting, Your professions | redesigned | "Tell me when a cooldown is ready"; links to its top earners, Leveling and Your crafts |
| Crafting, Craft queue | redesigned | "Missing to a list" asks which list; Search the AH; where crafting and selling happen |
| Guide | redesigned | An article opens the screen it describes and lists related articles; a new At the auction house article; the article list follows the tabs |
| Crafting, Top earners | redesigned | A quantity before Queue; "Reagents to a list" asks which list; Find a crafter left the Crafting pages |

## Decided while drawing (2026-11-24, to confirm)

- **One window, with or without the auction house** (the user's call, 2026-11-24): there is no Auction house tab.
  With the AH open the same tabs gain what the AH allows: Market searches it live, Item shows what's on sale with
  Buy and Sell yours, Portfolio gains Sell (your bags) and its Auctions can be cancelled. The title bar gains Full
  scan and "Use the game's AH".
- **Cancel per auction** is on the Auctions page (one click each, the game's rule). Without it you'd have to swap to
  the game's window to cancel. There is still no cancel scan.
- **Market overview is always there** as a mode; its Settings switch is gone. (If building its numbers costs too much
  per scan, the mode can build them when first opened.)
- **Signal and Score** both stay for now: Signal is the verdict, Score the default sort.
- **Shopping lists** stay in the Market sidebar: at the AH that is where you search and buy from them.
- **Tip words:** Sell, Craft, DE, Vendor (Craft replaces Arbitrate).
- **Requests** also go out as a whisper, so a crafter without AME sees them. A fair tip is suggested as about a tenth
  of what the craft adds.

## Planned drawings: the checklist

Where the plan comes from, in the user's own words and choices:

- "start with existing feature": every existing screen, in the new look and redesigned where the review found a
  problem (items 2-7, 16-17, 22, 24-32, 35-36);
- the tab set the user accepted (Home, Market, Item, Crafting, Guild, Portfolio, Guide): items 1 and 18-23;
- "the unified UI with AH open ... a view like the market view, and then an item view like a mix of the buy view in AH
  and the item view in AME": items 8-15;
- the "Still to draw" lists reported to the user on 2026-11-24, each answered with "carry on": the Guild pages, vendor
  selling, the session tracker, the game's AH window, the narrow boards, the Crafting pages, the tooltip, the Guide
  (items 13-15, 19-21, 25-37).

The plan is therefore every screen this review asked for (the Proposed direction above, and those lists). Each line names the board's file on the canvas. All 37 were opened on the canvas on 2026-11-24 after their
last change and render as described, except where the Checked column says otherwise. A script also checks every one of
the canvas's 72 board files (planned boards, shared components and untouched screens): listed in the index, every
value its markup uses supplied, every component it imports present, stylesheets linked. It reports no problems.

| # | Planned | Board | Page | Checked |
|---|---|---|---|---|
| 1 | Home: what to do now | `Home.dc.html` | New | viewed |
| 2 | Market, Screener: three modes, alerts, You hold | `Market.dc.html` | Existing | viewed |
| 3 | Market, Overview: the three-mode switch | `MarketOverview.dc.html` | Existing | viewed |
| 4 | Market, Arbitrage as a mode | `Arbitrage.dc.html` | Existing | viewed |
| 5 | Market with a shopping list picked | `ShoppingList.dc.html` | Existing | viewed |
| 6 | Market, narrow: modes as a dropdown | `MarketCompact.dc.html`, `MarketOverviewCompact.dc.html` | Existing | viewed |
| 7 | Item as a hub: action bar, position, other houses, crafting | `Main.dc.html` | Existing | viewed |
| 8 | At the AH: Market searches the AH | `MarketAH.dc.html` | New | viewed |
| 9 | At the AH: a shopping list, Search all, buying down the list | `MarketAHList.dc.html` | New | viewed |
| 10 | At the AH: Item with listings, Buy and Sell yours | `ItemAH.dc.html` | New | viewed |
| 11 | At the AH: Portfolio > Sell, Post and next | `AHSell.dc.html` | New | viewed |
| 12 | At the AH: Portfolio > Auctions, undercuts, Cancel | `AHAuctions.dc.html` | New | viewed |
| 13 | At the AH, narrow: Item | `ItemAHCompact.dc.html` | New | viewed |
| 14 | At the AH, narrow: Market | `MarketAHCompact.dc.html` | New | viewed |
| 15 | At the AH, narrow: Portfolio > Sell | `SellCompact.dc.html` | New | viewed |
| 16 | The game's AH window: Open in AME, the sell bar's ladder | `SellBar.dc.html` | Existing | viewed |
| 17 | Portfolio: Where, All characters, undercut count | `Portfolio.dc.html` | Existing | viewed |
| 18 | Guild: Crafters, with Ask | `CraftingCrafters.dc.html` | Existing | viewed |
| 19 | Guild: Requests | `GuildRequests.dc.html` | New | viewed |
| 20 | Guild: Your crafts | `GuildOffers.dc.html` | New | viewed |
| 21 | Guild: Guild lists | `GuildLists.dc.html` | New | viewed |
| 22 | Guild: Sharing prices (moved from Settings) | `Sync.dc.html` | Existing | viewed |
| 23 | Guild's pages (the sidebar) | `GuildNav.dc.html` | New | viewed |
| 24 | Settings: at the auction house; fonts and bars | `Settings.dc.html` | Existing | viewed |
| 25 | Crafting: Top earners, a quantity | `Crafting.dc.html` | Existing | viewed |
| 26 | Crafting: Recipes to buy, crafters and vendor recipes | `CraftingRecipes.dc.html` | Existing | viewed |
| 27 | Crafting: Sell or refine, Sell it raw | `CraftingRefine.dc.html` | Existing | viewed |
| 28 | Crafting: Leveling, recipes to the list too | `CraftingLeveling.dc.html` | Existing | viewed |
| 29 | Crafting: Your professions, cooldown notice | `CraftingProfessions.dc.html` | Existing | viewed |
| 30 | Crafting: Craft queue page | `CraftingQueuePage.dc.html` | Existing | viewed |
| 31 | The profession window's bar | `ProfBar.dc.html` | Existing | viewed, again after its side text was reworded |
| 32 | The craft queue panel | `CraftQueue.dc.html` | Existing | viewed |
| 33 | Vendor: sell | `VendorSell.dc.html` | New | viewed |
| 34 | Session tracker | `SessionTracker.dc.html` | New | viewed |
| 35 | Tooltip: Made by, and the way to the crafters | `Crafters.dc.html` | Existing | viewed |
| 36 | Guide: the Item article leads to its screen | `Guide.dc.html` | Existing | viewed |
| 37 | Guide: At the auction house | `GuideAH.dc.html` | New | viewed |

Not planned, and so not drawn: the other Guide articles' full text, and redrawn tooltips beyond the Made by line.
The theme and faction switches were tried on the canvas: on Market the theme turned the selected buttons, the picked
row and the active tab red (Horde), blue (Alliance) and gold (Goblin); on Home the faction turned "Azeroth" blue while
the accent stayed red. Both were set back to Horde. Every other window board sets the same two classes the same way
(the script checks that each one supplies them).

What only the user can do: confirm that these boards are what was wanted.

## The widget audit (started 2026-11-24)

The boards are being taken apart into widgets, so the canvas shows the same set the addon will register. A design
component takes data and has no children, which is the widget model: a screen is data handed to widgets. Chrome
that wraps content (the window, a panel, a card) cannot be a component there, so it is a shared class in `ame.css`
plus the chrome pieces that are components (title bar, status bar, the AH's tabs).

What the audit found, across 80 boards:

| Found | Where | Decision |
|---|---|---|
| The same style block copied into boards (`.fill` 37, `.lbl` 36, `.card` 22, `.ct` 19, `.in` 15, `.kv` 13...) | most screens | Done: one definition each in `ame.css`; 48 boards lost their copies |
| Headings in three sizes (`.h` at 14 and 15, `.ct` 14, panel title 15) | Guild, Crafting, Overview | Done: `.h` is the panel title (15) everywhere; `.ct` the card title (14) |
| Filter chips with their own colours | Market | Done: one `.chip`, colours from the tokens |
| The AH backdrop and tabs wrapper written out nine times | every at-the-AH board | Done: `.ahwrap` |
| Home, Home at the AH and the first run were three hand-written copies | Home | Done: one Home screen with a `state` prop; the other two boards are instances |
| Action rows (pill, two lines, value, button) hand-written | Home x3, the bell | Done: `ActionList` widget |
| KPI cards drawn two ways (Home's own, `KpiCard`) | Home vs Portfolio, Overview | Done: `KpiCard` everywhere |
| Item names as `.il` spans beside the `ItemLink` widget | Home, bell, minimap | Done on Home and the bell; the minimap tooltip still to do |

Second round (same day):

- **Item** is one screen (`Main.dc.html`) with an `ah` prop: it adds the Buy card and the AH's tabs, grows the
  window, and wakes Search and Sell. `ItemAH` is an instance.
- **Market > Lists** is one screen (`ShoppingList.dc.html`) with `ah`: the toolbar's buttons, the price column
  (Market or Lowest listing) and the buying bar under the table. `MarketAHList` is an instance.
- **PriceLadder** widget, with `dense` for the narrow window (the two drawings differed only in spacing); used on
  Sell and the narrow Sell. The Item page's "what to list at" card and the sell bar's buttons still draw their own.
- **Button**: the widget and the raw `.btn` spans draw the same (the widget uses the same classes), so there is one
  look; screens use the widget, and raw spans stay only inside other widgets.
- Not pairs after all: **Guide and Guide at the AH** are two articles of one screen (a prop for the article, not for
  the place); **Portfolio and Portfolio at the AH** are two views (Positions, Sell), and Sell only exists at the AH.
- **The narrow boards are layouts, not a prop**: each differs from its wide screen in most lines. In the addon a
  narrow window is a second layout tree over the same widgets.

Third round (same day):

- **Market** is one screen (`Market.dc.html`) with `ah`: the search box searches the auction house, the columns
  change to what is on sale now, and the picked row gets a panel on the right. `MarketAH` is an instance.
- **BuyCard** widget (on sale now, how many, Buy): Market's panel and the Item page had the same card written out
  twice.
- Market > Your alerts is still its own copy of Market; it is the same screen with another filter and columns, so
  it becomes a `view` prop.

Fourth round (same day): the list above, finished.

- **Market > Your alerts** is a view of the Market screen (`view` prop); its board is an instance.
- **Chart** widget: one chart fed by a named series (an item's history, the price index, the small 7-day line; wide
  and narrow). Five boards drew their own. Legends and axis labels stay the screen's.
- **KeyValue** (a label and its value) and **Field** (a text box with its label over it): 23 hand-written label
  rows and 9 text boxes replaced. Thirteen label rows stay written out because their value is more than money or
  text (an item link, a link, two values). **Input** now draws as the shared text box (it had its own background).
- **PriceLadder** has three layouts: rows (the Sell view's picker), buttons (the bar under the game's AH window),
  lines (the Item page's summary). All four places draw from it.
- **CraftingFilters** (search, the five filters, Leveling and Professions; `sections` adds Collapse all and the
  game's Filter menu) and **QueueStrip** (the queue as one line): five and four copies replaced.
- **The narrow boards** already drew from the shared widgets after the rounds above; the one raw text box left
  (narrow Item at the AH) is an Input.
- **Frames outside the window**: `FrameTitle` (title, note, close) on the session tracker, the vendor panel and the
  frame beside the game's profession window; that frame is redrawn in the window's look (the window's chrome,
  panel and card titles, tokens for every colour). `ProfBar` (the game's profession
  window with AME's Profit column) is redrawn from the shared widgets too: FrameTitle, DataTable, ItemLink,
  Button. In the game that frame, its list and its buttons are the game's own; only the Profit column is AME's.
- **Shell** is the documented region layout: header, toolbar, sidebar, main, right panel, status, laid out by row,
  column, grid and fill; a narrow window is a second layout of the same widgets.

The widget set the canvas now draws from: TitleBar, StatusBar, AHTabs, FrameTitle (chrome); Sidebar, Segmented,
SignalFilter, CraftingFilters (navigation and filters); DataTable, Chart, Card, KpiCard, ActionList, BuyCard,
PriceLadder, QueueStrip, SettingsCard (content); Button, Input, Field, Check, KeyValue, ItemLink, Money,
SignalBadge, Tag (primitives). Wrapping chrome is in `ame.css`: the window (`.ame`), a panel, a card, the AH
backdrop.

Not done, and why: the Existing screens page (the released addon's boards) is left as it is, since it records what
ships today. Guide's two boards are two articles of one screen and still two files. Portfolio's views (Positions,
Sell, Auctions) are separate files for separate views.

## Notifications outside the window (the author, 2026-11-24)

- **One AME sound** for what waits on you: a price alert firing, a craft request arriving, and (off by default) an
  auction selling or being undercut. The brief: its own sound, not to be mistaken for the common ones (coins, a
  bell), and not obtrusive (nothing like a "red alert"). Still to pick, by ear. It is offered through
  LibSharedMedia's sound list, AME's own first, and picking one in Settings plays it. A shipped file needs a licence
  that allows it; a sound already in the game needs no file.
- **The minimap button shows that something is waiting**: a mark and a count, the same count as the bell (unread
  notifications), cleared with it. Its tooltip lists what waits; a left-click opens AME on it.
- **The data broker entry shows the same**: text "AME" or "AME 3", the icon swapped to the lit one, the same tooltip.
- Drawn: `MinimapPending.dc.html`, the bell's panel `NotifyPanel.dc.html`, Settings > Notifications.

Also drawn 2026-11-24: the Sell view's card for a row tipped Craft, DE or Vendor (`AHSellTips.dc.html`), Home on
the first run (`HomeFirstRun.dc.html`), and Your alerts as the screener filtered (`MarketAlerts.dc.html`). Back and
Forward step through opened pages as a browser does, and the cog on Settings goes back; the prototype's player
keeps no history, so they are described on the title bar and not wired.

## Still to draw

Nothing planned is left. Next is the user's read of the boards, then building screen by screen, each done when an
in-game screenshot matches its board (docs/ux/design/README.md).
