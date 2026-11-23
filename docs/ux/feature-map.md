# Feature map

Every surface and feature, the stories it serves ([user-stories.md](user-stories.md)), and the other way round: which
stories have no feature. A feature with no story is a candidate to cut, merge or explain; a story with no feature is a
gap. Taken from a code read at c83b352 (Nov 2026).

## Surfaces

| Surface | Where | Reached from |
|---|---|---|
| AME window | Tabs: Market · Arbitrage · Portfolio · Crafting · Item · Guide; Settings behind the cog; bell | `/ame`, minimap/LDB/compartment, opens with the AH (setting), item clicks |
| AH frame | Shopping and Selling tabs (only without Auctionator), sell bar, scan button | The game's AH |
| Profession window | Row profit, bar, craft queue panel | The game's profession window |
| Vendor | "For your lists" panel | A merchant that sells something a list needs |
| Mailbox | Nothing visible (invoices read in the background) | — |
| Bags | Baganator corners and sort | Baganator |
| Tooltips | AME block, Shift details | Any item tooltip |
| Popups | Who can make it, prompts, menus | Item menu, `/ame who` |
| Chat | Alerts, scan announcements, version notice, slash output | — |

## Features → stories

### AME window: Market

| Feature | Stories | Notes |
|---|---|---|
| Screener table, signals, score | GOLD-1, FARM-3, BUY-5 | Signal and Score are two rankings with no guidance on which to trust |
| Category sidebar, quality/price/signal filters, chips | GOLD-1, FARM-3 | |
| Saved views, column chooser | GOLD-1 | Views don't save the list selection or columns |
| Watchlists in the sidebar, guild watchlists | ITEM-8, DATA-3 | No rename |
| Shopping lists in the Market sidebar | BUY-1, CRAFT-3 | Lists live in the screener's sidebar |
| Hidden items | GOLD-1 | Managed under Settings > Tooltips & charts |
| Market overview (KPIs, chart, movers, categories, largest) | GOLD-5 | Off by default |
| House picker (title bar) | DATA-9 | Drives only Market and Item |

### AME window: Item

| Feature | Stories | Notes |
|---|---|---|
| Chart (ranges, candles, layers, your trades) | ITEM-2, SELL-11 | |
| Verdict card | ITEM-2, SELL-4 | "Better: make X" only for vendor items |
| Market / stats cards | ITEM-2, DATA-6 | |
| Post at card (Quick/Normal/Patient) | SELL-1 | One unit; no Post button |
| Watch, alerts, hide | ITEM-8 | Alerts only managed here |
| Search box | ITEM-2 | Searches the viewed house only |

### AME window: Arbitrage, Portfolio

| Feature | Stories | Notes |
|---|---|---|
| Routes table, filters, route sidebar, depth | GOLD-4 | Row click selects (elsewhere it opens Item) |
| Portfolio KPIs, positions | WEALTH-1, GOLD-6 | |
| Ledger | WEALTH-2, GOLD-6 | No filter |
| Auctions | SELL-6 (partly) | No undercut flag, no cancel |
| Customers / Suppliers | WEALTH-5 | Names not actionable |
| Export | WEALTH-6 | Only Portfolio |

### AME window: Crafting

| Feature | Stories | Notes |
|---|---|---|
| Your professions | CRAFT-6, CRAFT-8, GOLD-8 | Cooldown column also carries instructions |
| Find a crafter | ASK-1 | Duplicates the Who can make it popup |
| Craft queue page | CRAFT-2, CRAFT-3 | "Missing to shopping list" replaces the list |
| Top earners (+ Tools) | GOLD-2, CRAFT-5 | Always 1 craft |
| Sell or refine | FARM-6 | |
| Recipes to buy | GOLD-3, HELP-4 | AH only |
| Leveling | CRAFT-4 | Own picker, crowded toolbar |

### AME window: Guide, Settings, notifications

| Feature | Stories | Notes |
|---|---|---|
| Guide articles, examples, search | LEARN-1, LEARN-4 | |
| Glossary, right-click explain | LEARN-2 | `marketDay` missing |
| Settings sections | LEARN-3, LEARN-6 | See redesign review on placement |
| Sharing (freshness, activity, guild, trusted, blocked) | DATA-3, DATA-4, DATA-5, DATA-7, HELP-1 | An operations page, kept inside Settings |
| Notifications bell | ITEM-8, DATA-5, DATA-10 | "+N older" can't be opened |

### AH frame

| Feature | Stories | Notes |
|---|---|---|
| Shopping tab: search, filters, results | BUY-6, BUY-10 | |
| Shopping tab: lists, Search all, Buy/Confirm | BUY-1, BUY-2, BUY-8 | Confirm-the-wrong-item bug (BUY-3) |
| Shopping tab: detail listings | BUY-7 | Only 5 |
| Selling tab: bags, Tip, Worth | SELL-2, SELL-4 | |
| Selling tab: ladder, form, Post | SELL-1, SELL-9 | One per click |
| Selling tab: On sale now | SELL-8 | |
| Sell bar | SELL-1, SELL-10 | Different layout from the Selling tab |
| Scan button, progress | DATA-2 | Hidden with Auctionator/TSM |
| Auctionator import | DATA-8 | |

### Elsewhere in the game

| Feature | Stories | Notes |
|---|---|---|
| Profession row profit, bar | CRAFT-1, CRAFT-3 | |
| Craft queue panel, Craft next | CRAFT-2 | |
| Who can make it popup | ASK-1, ASK-7 | See Find a crafter |
| Vendor "For your lists" panel | BUY-8 | Buys only |
| Mailbox invoice reading | WEALTH-2, SELL-1 (calibration) | Invisible |
| Tooltip block, Shift details, Made by | ITEM-1, ITEM-5, FARM-1, ASK-7 | |
| Baganator corners, worth sort | FARM-1, FARM-4 | Baganator only |
| Minimap/LDB/compartment, notifications feed | LEARN-5, ITEM-8 | Top buy signals not clickable |
| API v1 | LEARN-7 | No crafting calls |
| Slash commands | LEARN-5 | |

## Features with no story (cut, merge or justify)

| Feature | Verdict |
|---|---|
| `/ame item` history in chat | Duplicates the Item page. Drop, or keep as a power-user shortcut and say so |
| `crafting` setting | Read by nothing, no toggle. Remove, and the Guide's "With Crafting on" |
| Score column next to Signal | Two rankings. Merge into one explained ranking, or explain when each matters |
| `/ame status` engine internals | Developer data in a user command. Move internals to `/amedev`, keep a short status |
| Who can make it popup as a separate window | Same story as Find a crafter. Merge |
| Three "net" calculations | One story (SELL-9). One definition |

## Stories with no feature (gaps)

Grouped by size, smallest first.

- **Fixes:** BUY-3 (safe buying), BUY-7 (all gear listings), LEARN-4 (Guide mismatches).
- **Links between what exists:** SELL-5, CRAFT-7, ITEM-3, ITEM-4, ITEM-7, ASK-3, ASK-4, WEALTH-5, CRAFT-9.
- **New pieces on existing surfaces:** SELL-6 and SELL-7 (auctions and remembered prices), SELL-3 (post queue),
  BUY-4 (top-price buying), FARM-5 (vendor selling), GOLD-8 (cooldown notices), ITEM-8 (alerts
  list), BUY-9 (search terms and import).
- **New areas:** GOLD-7 (a home that says what to do now), FARM-2 (bag value and session gold per hour), ASK-2, ASK-5,
  ASK-6, HELP-2, HELP-3, HELP-5, HELP-6 (craft requests and offers).
- **Out of scope (decided):** WEALTH-3, WEALTH-4 (mail addons do it).
