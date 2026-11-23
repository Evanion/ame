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
- **Craft requests** between AME users (direction 7): wanted, to be designed.
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
- **Shift-click** links in chat (the game's meaning). **Ctrl-click**: dressing room. Searching the AH becomes a visible
  button, not a modifier.
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
| R1 | Canvas tokens + faction themes + parity pass | medium |
| R2 | Interaction contract, back/forward, one market, words | medium |
| R3 | Navigation (Home, Guild) and the Item hub, on the canvas first | large |
| R4 | AH workspace: post queue, auctions/cancel, buy loop, beside Auctionator, key bindings | large |
| R5 | Social crafting: requests, offers, tips | large |
| R6 | Farming, vendor selling, session tracker | medium |

The redesign itself (R1 onward on the canvas) runs on Claude Fable.

## Questions to settle before R3

1. Shift-click: give it back to the game everywhere (link to chat), with AH search as a button?

