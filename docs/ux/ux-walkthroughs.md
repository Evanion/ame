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

## Next

1. The user plays J1–J12 and marks each finding.
2. The agreed changes go onto the boards (design first), then the prototype is replayed.
3. Only then does building start, screen by screen.
