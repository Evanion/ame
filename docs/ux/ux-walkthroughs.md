# UX walkthroughs

The screens are drawn; this checks that they work as journeys. Each walkthrough is a story from
[user-stories.md](user-stories.md) taken step by step through the clickable prototype on the design canvas (start at
Home, press Play). A first pass was done by reading the flows end to end (2026-11-24); the findings below are from
that pass and are **not yet confirmed by a player trying them**.

How to use it: play each journey yourself, note where you hesitated or clicked wrong, and mark each finding agreed,
changed or dropped.

## What the prototype does and doesn't do

- Tabs, the cog, side menus, mode switches, item names and the main buttons lead to the board they would open.
- Each board is one example state: any item name opens Swiftthistle, any shopping list opens the example list.
- Inputs, filters, sorting, Confirm and Post change nothing.
- Home, Crafting, Guild, Guide and Settings are the same boards with or without the auction house, so going through
  one of them from an auction house board drops you back to the "away from the AH" versions.
- Back and forward in the title bar are drawn, not wired.

## Journeys

Clicks are counted from the window being open on Home.

| # | Journey | Stories | Path through the prototype | Clicks | First read |
|---|---|---|---|---|---|
| J1 | Sell what's in my bags | SELL-1, 2, 3 | Home: "Sell" on the bags row → Portfolio > Sell → Post, Post, Post… | 1 + one per item | Works. Found only through Home or by knowing it's under Portfolio (F1) |
| J2 | Sell one item I'm looking at | SELL-1, 11 | Item → "Post 120" → Item at the AH: Sell yours → Post | 2 | Works. Two places to sell from (F2) |
| J3 | Buy the mats on a list | BUY-1, 4, 8 | Market → the list in the sidebar → "Search the AH" → Search all → Confirm, Confirm… | 3 + one per item | Works. The list lives under Market (F3) |
| J4 | Find something and buy it | BUY-6, 7, 10 | Market at the AH: search → click a row → Item at the AH → Buy → Confirm | 4 | One screen more than the game's own AH; comparing several results means going back each time (F4) |
| J5 | Spot a deal from an alert | ITEM-8, GOLD-1 | Home: "Open" on the alert row → Item → "Search the AH" → Buy | 3 | Works |
| J6 | See what to craft, and do it | GOLD-2, CRAFT-2, 3, 7 | Crafting → Top earners → Queue → Craft queue → "Missing to a list" → the list → "Search the AH" → buy → (craft at the profession window) → Portfolio > Sell | 6 before crafting | Works, but it crosses three tabs (Crafting, Market, Portfolio) and the profession window (F5) |
| J7 | Ask a guildmate to craft | ASK-1…5 | Guild → Crafters → pick a recipe → "Ask" → "Send request" → Requests | 4 | Works |
| J8 | Fill a request | HELP-3, 6 | Home: "Answer" on the request row → Requests → Accept → Craft queue | 2 | Works. Nothing marks it done or collects the tip (F6) |
| J9 | Carry goods between houses | GOLD-4 | Market → Arbitrage → a route → "Search at the goblin AH" → buy | 3 | Works |
| J10 | Come home from farming | FARM-1…6 | Session tracker → "Open AME" → Home: "Sell" → Portfolio > Sell; vendor panel at a merchant | 2 | Works. "Craft" and "DE" tips in the bag list still lead nowhere (F7) |
| J11 | Level a profession | CRAFT-4 | Crafting → Your professions → Leveling → "Queue the steps" or the list button | 3 | Works |
| J12 | First session | LEARN-1 | Home → ? | — | No first-run path is drawn: Home assumes data, professions and a guild (F8) |

## Findings to settle

| # | Finding | Why it matters | Options |
|---|---|---|---|
| F1 | Selling at the AH is under Portfolio > Sell. A player who opens AME at the AH to sell has no "Sell" in sight unless Home shows the bags row. | The commonest task (Casual, Farmer) is one tab away under a word that means "what I own". | (a) At the AH the window opens on Portfolio > Sell when the bags hold something worth posting; (b) rename the tab at the AH ("Sell & auctions"); (c) keep, and rely on Home |
| F2 | One item can be posted from Item at the AH and from Portfolio > Sell. | Two forms to keep identical; which one remembers the price? | Keep both, one shared form and memory (recommended); or drop Sell yours from Item |
| F3 | Shopping lists live in the Market sidebar, and "Reagents to a list" from Crafting lands you on the Market tab. | A crafter thinks "my list", not "the market". | (a) Keep, since buying happens there; (b) give lists their own entry on Home; (c) a Lists tab |
| F4 | Search results → Item → back, for every result you want to compare. | Slower than the game's AH for browsing gear, and Back isn't wired yet. | (a) A listings panel beside the Market table at the AH (click a row, its listings and Buy show on the right, no page change); (b) keep, with Back/Forward and Escape |
| F5 | Crafting for profit crosses Crafting, Market and Portfolio, plus the profession window. | The flow that makes the most gold is the longest. | A "session" strip that follows you: queue → buy → craft → sell, with the next step as one button on every screen in the chain; or accept, since each step is one click |
| F6 | A request ends at Accept. | No done state, no tip collected, nothing tells the asker. | Add: Done (after the craft), a note to the asker, the tip recorded in the ledger |
| F7 | "Craft" and "DE" tips in the bag list have no action. | The review's first finding (advice with no button) is back in a new place. | Craft → queue that recipe; DE → Guild > Crafters for an enchanter, or disenchant if you can |
| F8 | No first-run state. | A new player sees an empty Home. | Draw Home with no data: scan, open your professions, join or trust someone; three steps with buttons |
| F9 | Home is the same with and without the AH. | At the AH its buttons could act (Sell, Review), away from it they can't. | Draw the AH version: the top rows become the AH tasks; away from the AH those buttons say "at the auction house" |
| F10 | Item, away from the AH: "Search the AH" and "Post" look active. | They can't work there. | Greyed with "at the auction house", or they queue the action for the next visit |
| F11 | "Your alerts" in the Market sidebar has no screen. | ITEM-8 asked for one place to manage alerts. | Draw it: the screener filtered to items with alerts, with the alert columns |
| F12 | The notification bell's panel isn't drawn in the new look. | It's on every title bar. | Draw it, with requests and cooldowns as kinds |
| F13 | Settings has no way back; Back and Forward aren't wired. | Easy to get lost in the prototype, and in the game today. | Wire Back/Forward in the prototype; Escape steps back |
| F14 | "Guild" also holds trusted friends who aren't in the guild. | The name promises less than the tab does. | Keep "Guild" (short, known), or "Network" (already rejected as a word), or "People" |

## Proposals

One proposal per finding, with what it changes on the boards. F1 is drawn; the rest wait for a yes or no.

### F1. Selling is hard to find: bottom tabs at the auction house (drawn)

While the auction house is open, three tabs hang under the window where the game's own AH frame has its tabs: **Buy**,
**Sell**, **Auctions**. They are shortcuts into the same screens the top tabs reach (Buy = Market searching the AH,
Sell = Portfolio > Sell, Auctions = Portfolio > Auctions), and the one you're in is lit. A new player sees the three
words they know from the game; the top row stays AME's own sections. Away from the auction house there are no bottom
tabs. Drawn on all eight auction house boards (component `AHTabs`).

Also proposed: at the auction house the window **opens on Sell** when your bags hold something worth posting, else on
Buy.

### F2. Two places to post one item

Keep both, as **one form**: the same component on Item at the AH ("Sell yours") and on Portfolio > Sell, with one
memory of last price and duration per item. Posting from either updates the other. No board change beyond naming them
the same ("Sell yours" on both).

### F3. Shopping lists live under Market

Keep the lists in the Market sidebar (buying happens there), and add two ways in so a crafter never has to know that:
- **Home** gets a "Lists" row when a list still needs something: "potions: 3 items to buy, about 4g" with "Buy" (at the
  AH) or "Open".
- **"Reagents to a list"** stops jumping tabs: it adds, shows "Added to potions" with an "Open the list" link, and
  leaves you where you were.

### F4. Browsing to buy takes a screen per result

At the auction house, Market gets a **listings panel on the right** (the place Arbitrage already uses for its route):
click a row and its listings, Buy, Confirm and Cancel show beside the table, with no page change. The item's name in
the panel still opens the full Item page for the chart. Arrow keys move the picked row, so comparing ten swords is ten
key presses. The Item page at the AH stays as it is, for when you arrive from elsewhere.

### F5. Crafting for profit crosses three tabs

A **"next step" strip** above the status row, shown while the craft queue has work in it:
"Craft queue: 3 steps · next: buy 5 Mithril Ore" with one button that does the next thing for where you are (Search
all at the AH, Craft next at the profession window, Sell when the results are in your bags). It follows you across
tabs, so the chain reads as one job. The queue page stays the full view.

### F6. A request ends at Accept

The request gets its whole life on Requests:
- states **new → accepted → crafted → handed over**; "Mark crafted" appears when the queue step is done, "Handed over"
  closes it;
- the asker's side shows the same states and gets a notice at each change;
- the tip is typed (prefilled with the offer) at "Handed over" and lands in the Ledger as income, with the mats you
  provided as cost.

### F7. "Craft" and "DE" tips have no button

In Portfolio > Sell, picking a row whose tip isn't Sell swaps the posting form's main button:
- **Craft**: "Queue 5 Bolt of Silk Cloth" (the recipe that makes it worth more), with what that nets against selling raw;
- **DE**: "Disenchant" when one of yours is an enchanter (it goes to that character's to-do), else "Find an enchanter"
  (Guild > Crafters, Enchanting);
- **Vendor**: "Sell at a vendor" does nothing here but says so: the vendor panel takes it at the next merchant.
Posting anyway stays possible as the second button.

### F8. No first-run state

Home with nothing yet shows **three steps**, each with its button and a tick when done: "Scan the auction house" (at
the AH: Full scan; away: "visit an auction house"), "Open your profession windows once" (lists which are missing),
"Share with your guild" (on by default: shows who else has AME, or how to trust a friend). The normal Home replaces
each step as its data arrives.

### F9. Home is the same with and without the AH

One Home, two states of its buttons:
- **at the AH** the rows that need it act: Sell, Review (auctions), Buy (lists);
- **away** those rows stay but their button reads "At the AH" (greyed), and the rows you can act on anywhere (alerts,
  cooldowns, requests, crafting) sort to the top.

### F10. "Search the AH" and "Post" look active away from the AH

Same rule everywhere: a button that needs the auction house is **greyed with "At the AH"** as its hover text, never
hidden (so you learn it exists) and never a chat error. On the Item page, "Add to a shopping list" stays the action
that works anywhere.

### F11. "Your alerts" has no screen

It is the **screener filtered to items with alerts**, with three extra columns: Below, Above, Last fired. Right-click
a row to change or remove its alert; a bell marks those rows in every other list. No new page type.

### F12. The notification bell's panel

Redrawn in the new look as a **panel under the bell**: kinds are alert, request, cooldown, sharing and version; each
row opens its screen (alert → Item, request → Requests, cooldown → the craft queue); it scrolls; "Clear all". Home's
"To do now" is the same list filtered to what you can act on, so the two never disagree.

### F13. No way back

- **Back and Forward** in the title bar keep a history of screens and items (wired in the prototype too).
- **Escape** steps back once, and closes the window only from where you started.
- **Settings** opens over the screen you were on and closes back to it.

### F14. "Guild" holds non-guild friends too

Keep the name **Guild**: short, and true for nearly everyone. Inside it, trusted players who aren't guildmates are
marked "trusted" (as the Crafters list already does), and the Sharing page's heading reads "Guild and trusted players".

### What I'd do first

F4 (listings beside the table) and F13 (Back and Forward) change how buying feels the most. F7, F9 and F10 are one
rule applied in three places: every piece of advice has a button, and a button that can't work says why. F8 is the
first thing a new player sees.

## The user's read of the proposals (2026-11-24)

| Finding | Answer | State |
|---|---|---|
| Compare | Screens that differ at the auction house must be seen side by side | Done: canvas page "Away vs at the AH", in pairs (Home, Market, Item, Portfolio) |
| Open on Sell | Rejected as proposed: players always have something sellable, so the rule would always pick Sell | Changed: at the AH the window opens where you last were at the AH (Buy the first time) |
| F1 bottom tabs | Asked for | Drawn |
| F2 | Don't sell on the Item page: it confuses, and it cost the page its stats when they matter most. "On sale now" becomes a sidebar card called Buy. The only difference at the AH: Item gains that card | Redrawn: Item at the AH is the full Item page plus a Buy card; "Sell 120" goes to Sell |
| F3 lists | Reconsider, then: try A | Drawn: Lists is a fourth mode of Market (away and at the AH, on the compare page) |
| F4 | The proposal wasn't findable | Drawn so it can be seen: Market at the AH, right-hand panel (the picked row's listings and the same Buy card) |
| F5 | Why several screens: one screen with the recipes and whether each is ready to craft; then: sketch it out | Sketched in three states: All, Ready now, To learn (New screens). The Crafting tab opens it |
| F6-F13 | OK | To draw: requests' states, Sell's Craft/DE buttons, first run, alerts list, bell panel, Back/Forward. F9/F10 drawn (Home at the AH; greyed "At the AH" buttons on Home and Item) |
| F14 | "Social" in code, "Guild" in translation strings | Decided: the tab reads Guild; its code name (module, keys, slash word) is `social` |

### F3, reconsidered: where shopping lists live (decided: A, to try)

What a list is for: made from a recipe, an item or a guildmate's list; used at the auction house (and vendors) to buy.

| Option | What it means | For | Against |
|---|---|---|---|
| **A. Lists is a mode of Market** (recommended) | Market's modes become Screener · Overview · Arbitrage · Lists. Lists shows every list on the left (yours, the guild's, watchlists too) and the picked one on the right. The Screener's sidebar keeps watchlists only as filters. At the AH, Buy opens on Lists when one still needs something | A named place, no new tab, and it is where buying happens | Market gets a fourth mode |
| B. Lists under Buy only | Lists exist only at the AH, under the Buy bottom tab; away from it you reach them from Home | Matches when they're used | You can't plan a list away from the AH without going through Home |
| C. A Lists tab | An eighth top tab | Most visible | The tab row is full, and lists aren't a daily destination |
| D. As now | In the Market sidebar | No change | The finding stands |

Whichever is picked: "Reagents to a list" adds without changing tab, and says where it went.

### F5: Crafting as one screen

Drawn (New screens, "Proposal · Crafting as one screen"): one table of every recipe your characters can make, with a
**Ready** column: "ready ×3", "1 now · missing 6 Mountain Silversage", "needs a tool", "cooldown: 14 h", "learn it:
recipe 72g on the AH". Filters: All · Ready now · Queued · Missing something · To learn. The picked recipe's needs are
on the right with Queue and "Buy what's missing"; the queue is one line under the table. Top earners, Sell or refine,
Recipes to buy and the Craft queue page fold into it (as the sort, the filters and that line); Leveling and Your
professions stay as buttons to their pages. If agreed, the six Crafting pages become this one plus those two.

#### F5, after the sketch: the game's structure (2026-11-23)

The user's read of the sketch: "All" would list every recipe on every character, which is too long; do it as the
game's window does, a tab per profession and its sections ("Agility food", "Caster Elixirs", "One-handed Swords");
merged crafting must be as good as or better than the game's own. Research:
`reports/Crafting UI pain points and wishes.md` (thin on direct player quotes; mostly forum threads and what addons
supply).

| Finding | What it means here |
|---|---|
| WoW Forever ships the modern profession window: a tab per profession, search, filters, recipe tracking | That window is the bar, not the vanilla one |
| The most-liked complaints: the window is too big and fights the auction house | Crafting inside the AME window answers it by construction |
| It forgets: filters, "show unlearned" and folded sections reset; no Collapse All | Remember all of it; have Collapse all |
| Skill-up cues got harder to read | Keep the orange, yellow, green, grey colour on each row |
| Every crafting-window addon has a saved queue, a shopping list that subtracts bags, bank and alts, vendor buying, cross-alt counts | Table stakes |
| None uses one long list as its main view; flat lists serve "who can make X" and "what pays" | Sections by default; All professions as a view |
| TSM's setup is the standing complaint; the Skillet price plugin is stale; GuildCrafts (129K) is abandoned | Profit with no setup, and the guild's crafters, are where to win (inferred) |

Redrawn (New screens): the professions your characters have are listed on the left with their skill; a profession
shows its recipes in the game's sections, foldable, with Collapse all, the skill-up colour and the Ready column.
"All professions" is the flat list across characters (drawn on Ready now and To learn). To check in game: the section
names (placeholders on the board) and whether the game's window has favourites.

### F14: the tab's name

| Name | Reads as | Note |
|---|---|---|
| **Guild** (keep) | Your guild | Short and known; trusted friends are marked "trusted" inside |
| **Social** | The game's own word for friends and guild (its Social window) | Covers trusted friends honestly; a little vague for "who can craft this" |
| Crafters | What most people come for | Leaves out lists and sharing prices |
| Community | Guild and friends | Long for a tab |

Decided: the code calls it **social** (it holds guildmates and trusted friends), and every string the player sees
says **Guild**.

## Next

1. The user plays J1–J12 and marks each finding.
2. The agreed changes go onto the boards (design first), then the prototype is replayed.
3. Only then does building start, screen by screen.
