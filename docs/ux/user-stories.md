# User stories

What players do with AME, written from where they are and what they're trying to get done. Every feature should serve
at least one story here; [feature-map.md](feature-map.md) checks that both ways, and
[redesign-review.md](redesign-review.md) says what to change.

AME is not a price-graph addon any more: it records the market, prices your posts, buys from lists, plans crafts across
alts, finds crafters in the guild and shares all of it. A player switching from Auctionator, TSM or AHDB should be able
to do their daily routine in AME alone.

Status: **✓** the story works today · **◐** partly (a step is missing, slow or hard to find) · **✗** not supported.
IDs are stable: refer to stories by ID in plans, commits and the design canvas.

## Who plays

| Persona | Plays like | Cares about |
|---|---|---|
| **Casual** | Levels, loots, visits the AH now and then | A fair price without thinking; not getting ripped off |
| **Farmer** | Gathers herbs, ore, cloth, leather out in the world | What's worth farming; what the bags are worth; selling the haul fast |
| **Crafter** | One or more professions, often spread over alts | What's profitable to make today; levelling cheaply; buying mats; cooldowns |
| **Trader** | Flips items, carries goods between houses | Buying under value, selling over it; position and profit; speed |
| **Customer** | Needs a craft or an enchant they can't do | Who can make it, what to bring, what to tip |
| **Guildie** | Part of a guild that uses AME | Sharing scans and recipes; helping others; guild lists |
| **Switcher** | Comes from Auctionator / TSM / AHDB | Their daily routine working at least as fast as before |

Personas overlap: most players are a Casual who sometimes farms, a Crafter on one alt and a Customer on another.

## Where they are

The stories are grouped by the situation the player is in, because that decides which surface they can reach: the AH
frame, the profession window, a vendor, the mailbox, their bags, or the AME window anywhere.

| Code | Situation |
|---|---|
| SELL | At the auction house, selling |
| BUY | At the auction house, buying |
| FARM | Out in the world, gathering or looting |
| GOLD | Looking for a way to earn gold (anywhere) |
| CRAFT | Crafting for themselves: at the profession window or planning |
| ASK | Needing someone else to craft or enchant |
| HELP | Crafting or enchanting for someone else |
| WEALTH | Managing what they own across alts: bags, bank, mail, auctions |
| ITEM | Looking at one item, anywhere |
| DATA | Keeping prices fresh, sharing and trusting them |
| LEARN | Learning AME and configuring it |

---

## SELL: at the auction house, selling

| ID | As a… | I want to… | so that… | Status | Surfaces today |
|---|---|---|---|---|---|
| SELL-1 | Casual | see a price for the item I'm posting, with how fast it sells | I don't undercut by half or sit on it for days | ✓ | Sell bar, Selling tab ladder |
| SELL-2 | Farmer | see everything in my bags worth posting, most valuable first | I post the haul without checking each item | ✓ | Selling tab "In your bags" (Worth, Tip) |
| SELL-3 | Farmer, Switcher | post a whole bag (or a group) in one pass, each at its suggested price | posting 30 stacks takes a minute, not ten | ✗ | One item per click, no next item, gear 1 per click |
| SELL-4 | Any | be told when an item pays more at a vendor, from crafting it first, or disenchanting it | I take the best outcome, not just the AH | ◐ | Tip column, hints; no action button for any of them |
| SELL-5 | Crafter | go from "make it first" straight to queueing that craft | the tip turns into action | ✗ | Text only |
| SELL-6 | Trader, Switcher | see which of my auctions are undercut, to cancel them in the game's window and repost | my auctions stay at the front of the queue | ✗ | Portfolio > Auctions lists them, no undercut flag |
| SELL-7 | Switcher | have AME remember my last price and duration per item | reposting is one click | ✗ | Not remembered |
| SELL-8 | Any | undercut or match a specific listing deliberately | I control the price when I want to | ◐ | Click a listing = 1c under; no match |
| SELL-9 | Any | know what I net after the cut and the deposit, one way everywhere | the numbers agree with each other | ◐ | Three different "net" calculations |
| SELL-10 | Auctionator user | get AME's prices inside Auctionator's selling tab | I don't have to switch addons | ✓ | Sell bar follows Auctionator |
| SELL-11 | Any | see how an item's price is moving before I post a big stack | I don't dump into a falling market | ◐ | Chart only if the AME window is open on Item |

## BUY: at the auction house, buying

| ID | As a… | I want to… | so that… | Status | Surfaces today |
|---|---|---|---|---|---|
| BUY-1 | Crafter | buy everything on my list in one go, up to the amount I still need | stocking up for a craft session is quick | ◐ | Search all + per-item Buy/Confirm, next item by hand |
| BUY-2 | Any | be warned before paying much more than the listings shown | I don't overpay when prices move | ✓ | Price jump warning |
| BUY-3 | Any | never buy a different item than the one on screen, and back out of a purchase | buying is safe | ✗ | Buy confirms any pending purchase; no Cancel |
| BUY-4 | Trader | buy only what's under my top price, automatically | I don't have to check each listing | ✗ | Top price only marks rows |
| BUY-5 | Trader | see deals: items listed well under their market value right now | I catch bargains | ◐ | Screener score (offline); no live deal finder |
| BUY-6 | Any | search the AH like the default UI (filters, categories) with AME's market view on every row | I see value, not just price | ✓ | Shopping tab search + filters |
| BUY-7 | Any | see all listings of a piece of gear, not just the cheapest few | I can buy the one with the right stats | ✗ | Only 5 listings |
| BUY-8 | Crafter | skip what a vendor sells, and buy it at the vendor in the right amount | I don't pay AH prices for vendor goods | ✓ | "vendor" mark, vendor panel |
| BUY-9 | Switcher | use search-term lists ("of the Bear", price caps) and import my Auctionator lists | my old lists keep working | ✗ | Exact items only, no import |
| BUY-10 | Any | jump from what I'm buying to its history, and add a result to my list in one click | buying and planning stay connected | ◐ | Chart via link; adding takes 4 steps |
| BUY-11 | Auctionator user | keep Auctionator for the AH, with AME as its sidecar | I choose my AH addon | ✓ | AME's tabs step aside when Auctionator is loaded (decided: no mode to show both) |

## FARM: out in the world

| ID | As a… | I want to… | so that… | Status | Surfaces today |
|---|---|---|---|---|---|
| FARM-1 | Farmer | see what anything I loot is worth, and whether it sells | I know what to keep | ✓ | Tooltip, Baganator corners |
| FARM-2 | Farmer | know what my bags are worth right now, and what I've made this session | I see gold per hour and when to go sell | ✗ | Portfolio holdings only, no session |
| FARM-3 | Farmer | know which mats are worth farming at the moment (price × how fast they sell) | I farm the right node | ◐ | Screener can filter Trade Goods; no "farm this" view |
| FARM-4 | Farmer | see in my bags what to sell, vendor, disenchant or craft first | I clear bags without thinking | ◐ | Baganator only; tip corner not placed by default |
| FARM-5 | Farmer | sell vendor-tip items and junk at a vendor in one click | bag space is free and nothing valuable goes by mistake | ✗ | Nothing for selling at vendors |
| FARM-6 | Farmer, Crafter | decide whether to sell mats raw or refine them first | I take the better price | ✓ | Crafting > Sell or refine |
| FARM-7 | Farmer | get told when a farmed mat's price spikes or drops past my alert | I know when to farm or sell | ◐ | Alerts exist, set one item at a time, no list of them |

## GOLD: looking for a way to earn gold

| ID | As a… | I want to… | so that… | Status | Surfaces today |
|---|---|---|---|---|---|
| GOLD-1 | Trader | find items that are cheap against their usual price and sell well | I buy low and sell high | ✓ | Market screener, signals |
| GOLD-2 | Crafter | see what my recipes earn today, across all my alts | I craft what pays | ✓ | Top earners |
| GOLD-3 | Crafter | find recipes worth buying (AH and vendor) and how fast they pay back | I invest in the right recipe | ◐ | Recipes to buy: AH only, no vendor recipes |
| GOLD-4 | Trader | carry goods between auction houses for profit, knowing how many before the edge is gone | cross-house trading is worth the trip | ✓ | Arbitrage, depth |
| GOLD-5 | Any | see where the market is going (dearer, cheaper, what's moving) | I time big moves | ◐ | Market overview, off by default |
| GOLD-6 | Trader | track my profit, realised and on paper | I know what works | ✓ | Portfolio |
| GOLD-7 | Any | open AME and see "what should I do now": alerts, undercuts, cooldowns, top opportunities | I don't hunt through tabs | ✗ | No home or summary |
| GOLD-8 | Crafter | be told when a profession cooldown is ready | I don't waste a transmute day | ✗ | Cooldown column only |

## CRAFT: crafting for myself

| ID | As a… | I want to… | so that… | Status | Surfaces today |
|---|---|---|---|---|---|
| CRAFT-1 | Crafter | see at the profession window what each recipe makes in profit | I pick a good craft on the spot | ✓ | Row profit, bar |
| CRAFT-2 | Crafter | queue crafts across alts and see, in order, what to buy, fetch, mail and craft | a batch session runs itself | ✓ | Craft queue (page and panel) |
| CRAFT-3 | Crafter | put what's missing on a shopping list and buy it at the AH | mats arrive without spreadsheets | ◐ | Four different "reagents to a list" behaviours |
| CRAFT-4 | Crafter | level a profession cheapest, fastest or with my mats, with the recipes I must learn on the way | levelling doesn't cost a fortune | ✓ | Leveling |
| CRAFT-5 | Crafter | know which tools and places a recipe needs and how to get them | I'm not stuck at the anvil without a hammer | ✓ | Tools section |
| CRAFT-6 | Crafter | see all my alts' professions, skills and recipes at a glance | I know who can do what | ✓ | Your professions |
| CRAFT-7 | Crafter | sell what I just crafted without hunting for it | crafting turns into gold | ✗ | No link from crafting to selling |
| CRAFT-8 | Crafter | get recipes recorded without opening every profession on every alt | the data is there from day one | ◐ | Must open each window once; no checklist |
| CRAFT-9 | Crafter | craft a quantity (not one) from Top earners | I plan a real batch | ✗ | Always 1 |

## ASK: I need someone to craft or enchant for me

| ID | As a… | I want to… | so that… | Status | Surfaces today |
|---|---|---|---|---|---|
| ASK-1 | Customer | find who in my guild (or trusted friends) can make an item or enchant, online first | I know whom to ask | ◐ | Find a crafter page and Who can make it popup: two versions |
| ASK-2 | Customer | send a ready-made request: the item, the mats I'll bring, a fair tip | asking is one click and polite | ✗ | Whisper with a link only |
| ASK-3 | Customer | buy the mats for a craft I'll ask someone to do | I arrive with everything | ✗ | No reagents-to-list from a crafter |
| ASK-4 | Customer | know what's fair to pay: mats cost against the product's price | neither of us is short-changed | ✗ | Numbers exist, not offered |
| ASK-5 | Customer | track what I asked for, from whom, and whether it's done | nothing gets forgotten | ✗ | — |
| ASK-6 | Customer | reach a crafter who is offline | I'm not limited to who's on now | ✗ | No request or mail path; trusted players always show offline |
| ASK-7 | Customer | see "made by" for anything I look at | I learn who to ask as I browse | ◐ | Shift tooltip, names not clickable |

## HELP: crafting or enchanting for others

| ID | As a… | I want to… | so that… | Status | Surfaces today |
|---|---|---|---|---|---|
| HELP-1 | Crafter, Guildie | share what my characters can craft | guildmates find me | ✓ | Recipe sharing (on by default) |
| HELP-2 | Crafter | advertise what I make, with links and prices, in trade or guild chat | I get customers | ✗ | — |
| HELP-3 | Crafter | receive requests in AME, accept them and mark them done | I don't lose track of orders | ✗ | — |
| HELP-4 | Crafter | see what my guild asks for most, and which recipes nobody has | I learn what's needed | ◐ | Recipes to buy "Only what nobody has" |
| HELP-5 | Enchanter | be found by people with gear to disenchant or enchant | my profession earns too | ✗ | DE signal says "sell it to an enchanter", no link |
| HELP-6 | Crafter | quote a price for a craft: mats, product value, my cut | I charge fairly | ✗ | — |

## WEALTH: what I own across alts

| ID | As a… | I want to… | so that… | Status | Surfaces today |
|---|---|---|---|---|---|
| WEALTH-1 | Any | see what I hold, where (bags, bank, mail, auctions, alts) and what it's worth | I know my net worth | ✓ | Portfolio positions, tooltip |
| WEALTH-2 | Trader | see my sales, purchases and profit by period | I know my income | ✓ | Portfolio ledger |
| WEALTH-3 | Any | collect all mail and AH gold in one click | the mailbox isn't a chore | out | Left to mail addons (decided) |
| WEALTH-4 | Crafter | send mats to the alt that crafts them | the craft queue's "mail them over" step is easy | out | Left to mail addons; the queue says what to send |
| WEALTH-5 | Trader | see who buys from me and who I buy from, and contact them | I build regular trade | ◐ | Customers/Suppliers, names not actionable |
| WEALTH-6 | Any | export my data | I can work in a spreadsheet | ◐ | Portfolio export only |

## ITEM: looking at one item

| ID | As a… | I want to… | so that… | Status | Surfaces today |
|---|---|---|---|---|---|
| ITEM-1 | Any | price-check anything from its tooltip, anywhere | I don't open AME | ✓ | Tooltip |
| ITEM-2 | Any | see an item's history, verdict and posting price on one page | I decide buy, hold or sell | ✓ | Item page |
| ITEM-3 | Any | act from the item page: search the AH, buy, post, add to a list, ask a crafter, make it | the analysis leads somewhere | ✗ | Item page has no actions beyond Watch and alerts |
| ITEM-4 | Any | see on the item page what I own of it and what I paid | the verdict is about my position | ✗ | Tooltip and Portfolio only |
| ITEM-5 | Trader | compare the item across auction houses | I see where it sells best | ◐ | Shift tooltip; Item page shows one house |
| ITEM-6 | Crafter | see what an item is made from, what it's used in, and who makes it | I follow the crafting chain | ◐ | "Make X" verdict for vendor items only |
| ITEM-7 | Any | go back to where I came from | browsing doesn't lose my place | ✗ | No back, Escape closes the window |
| ITEM-8 | Any | watch an item and get alerts, and manage all my alerts in one place | I follow the items I care about | ◐ | Alerts are per item, no list |

## DATA: keeping prices fresh, sharing, trusting

| ID | As a… | I want to… | so that… | Status | Surfaces today |
|---|---|---|---|---|---|
| DATA-1 | Any | get prices recorded from any scan, any addon, without extra work | data builds up by itself | ✓ | Passive recording |
| DATA-2 | Any | run a full or fast scan from AME | I'm not dependent on another addon | ◐ | Button hidden when Auctionator/TSM are loaded |
| DATA-3 | Guildie | get my guild's scans automatically, and share mine | nobody has to scan every day | ✓ | Guild sync |
| DATA-4 | Guildie | see what's syncing, from whom, how long it takes, and fix a stuck transfer | I trust that sharing works | ✓ | Sync activity (inside Settings) |
| DATA-5 | Any | swap data with a friend or my own characters on another account | small groups benefit too | ✓ | Trusted players |
| DATA-6 | Any | know how much to trust a number (fresh, scans, outliers) | I don't act on stale data | ✓ | Confidence, ages, outlier filter |
| DATA-7 | Officer | block someone sending bad data, guild-wide | the shared market stays honest | ✓ | Blocklists, guild info line |
| DATA-8 | Switcher | keep my Auctionator history when switching | charts aren't empty on day one | ✓ | Import |
| DATA-9 | Any | know the market I'm looking at and switch houses consistently | all numbers on screen come from the same AH | ◐ | House picker drives only Market and Item |
| DATA-10 | Any | know when a newer AME is out | I'm not running old code | ✓ | Version notice |

## LEARN: learning and configuring AME

| ID | As a… | I want to… | so that… | Status | Surfaces today |
|---|---|---|---|---|---|
| LEARN-1 | New player | be walked through the first scan, first sell and first craft | I see the value in ten minutes | ◐ | Guide + one-time hints, no first-run path |
| LEARN-2 | Any | get an explanation of any number where I see it | I understand what I'm told | ✓ | Hover + right-click glossary |
| LEARN-3 | Any | find a setting next to the feature it changes | I don't search through Settings | ◐ | Several settings far from their feature |
| LEARN-4 | Any | trust that the Guide matches what I see | the help helps | ◐ | About 15 mismatches found |
| LEARN-5 | Any | open any part of AME by key binding or command | it fits my routine | ◐ | No key bindings; some pages unreachable by command |
| LEARN-6 | Any | see AME in my faction's colours (Horde, Alliance, goblin) | it feels part of the game | ✓ | Themes |
| LEARN-7 | Addon author | read AME's prices and signals from my addon | AME works with the rest of my UI | ✓ | API v1, Baganator plugin |
