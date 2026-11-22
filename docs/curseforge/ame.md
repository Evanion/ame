**Azeroth Mercantile Exchange (AME)** turns the auction house into a trading floor: price history, charts and buy and sell signals for every item, posting prices that sell, arbitrage between auction houses, your portfolio, and what your professions earn.

Most auction addons tell you what an item costs right now. AME tells you where the price has been, where it's heading, whether you'll be able to sell, what your stock is worth, and what's worth crafting. Scan or search the auction house the way you already do, and AME builds the market picture in the background.

## What you can do with AME

### Read the market

- **Read the chart before you buy.** Price and volume charts for any item, built from every scan you and your guild make. See the last two days scan by scan, a week hour by hour, or the item's whole history. Switch between lines and candlesticks, add MA 20 and the 7-day average, and hover any point for its price and volume.
- **Know when to buy and when to sell.** Every item gets a signal: Buy, Hold or Sell against its own history; Wait when sellers are dumping; Vendor when a vendor pays more than the auction house after the cut; DE when gear is worth more disenchanted.
- **See what the market is doing.** AME reads price against supply to tell a real shortage from sellers piling in, or a quiet market from someone dumping stock.
- **Find the deals you didn't know to look for.** The market screener ranks everything on the auction house. Filter by category, quality, price and signal, save your views, and sort by any column.
- **Count what really sells.** Scans can't tell a sale from an expired listing, so AME learns from real auction outcomes, yours and your guild's. An item reposted every day that never sells no longer looks like a bestseller.
- **Get the big picture** (optional). The market overview shows the whole auction house like a stock exchange: a market index, a CPI, turnover, and the biggest risers and fallers.

### Buy and sell

- **Post at a price that sells.** Instead of undercutting by 1c, AME suggests Quick, Normal and Patient prices from the listings ahead of you, how fast the item sells and how often it gets undercut. A bar under the sell window fills in the price with one click.
- **Shop and sell from AME's own auction house tabs.** Without Auctionator, the auction house gets a Shopping tab (filtered search with AME's signals on every result, your shopping lists, and a warning when a bulk buy costs more than the listings shown) and a Selling tab (what in your bags is worth listing, with AME's prices and one-click posting).
- **Don't get stuck with stock.** See roughly how many of an item sell each day and how long your stack would take to move. Before you buy in bulk, see what 20 units would actually cost, not just the cheapest one.
- **Shopping lists that count down.** List what you need for a goal. AME subtracts what all your characters already hold, crosses off what you buy, and searches the auction house for the rest. At a vendor that sells something on your lists, a panel beside the merchant buys the right amount in one click.
- **Trade between auction houses.** Compare the Alliance, Horde and goblin auction houses side by side. Profits are shown after the auction house cut and deposit, along with how many units you can buy before the deal runs out ("buy 37, +12g").

### Craft for profit

- **See what your professions earn.** AME learns your recipes from your profession windows, on every character, and ranks them by profit at today's prices.
- **Sell or refine?** For the materials you hold: sell them raw, or craft them into something worth more first.
- **Recipes worth buying.** Recipes on the auction house that one of your characters could learn, ranked by how fast they pay back, with a check of who in your guild already knows each one.
- **Level up for less.** The cheapest way to raise a profession to the skill you pick, recalculated from today's prices.
- **Profit in the profession window.** Profit on every recipe, a craft queue that works out the parts first and where each material comes from (bags, bank, an alt, a guild bank, a vendor or the auction house), and a Craft next button.
- **Find a crafter.** Search an item or enchant to see who in your guild, or among your trusted players, can make it, and whisper them with the recipe linked.

### Keep track

- **Track your portfolio.** AME reads your auction mail to log what you bought and sold, counts what you hold across bags, bank, mailbox and auctions on every character, and shows your profit or loss on each item.
- **Tooltips that answer the question.** Market price each and for all you have, what you hold on every character and guild bank, the disenchant value, how fast it sells and its signal. Hold Shift for more.
- **Keep watchlists and set alerts.** Follow the items you trade and get an alert when they cross a price or turn Buy or Sell. Alerts wait under a bell in the window, and on your info bar (LibDataBroker).
- **Know how much to trust a number.** Every item shows a high, medium or low confidence marker, based on how much recent data AME has for it.

### Trade together

- **Share with your guild.** When a guildmate or trusted friend with AME scans, everyone's prices update. Players who were offline catch up when they log in.
- **Share lists and recipes.** Share watchlists and shopping lists with your guild, and see who can craft what.
- **Sync that stays out of the way.** Sync pauses in combat and never freezes your game. Data from others never overwrites your own, and suspicious prices are filtered out.

## Getting started

1. Install AME and log in. AME Crafting Data is installed with it: it holds the recipe data and loads only when you open the Crafting tab.
2. Visit the auction house and scan or search as usual. AME works with the default auction house and with scanning addons like Auctionator. Without one, use the **Full scan** button AME adds to the auction house window.
3. Type `/ame` to open the exchange, or `/ame <item link>` to chart an item. You can also set a modifier click to open any item's chart (Settings, General).
4. Open each of your professions once on every character, so AME knows what they can craft.

Already use Auctionator? AME can import your existing price history the first time you run it, so your charts aren't empty on day one.

The more often you scan, the sharper your charts and signals get. Prices are tracked separately for each realm and each auction house.

The window's **Guide** tab covers every feature, with a glossary of every number AME shows.

## Commands

- `/ame` opens the exchange.
- `/ame <item link>` charts an item.
- `/ame scan` runs a full scan at the auction house.
- `/ame who <item>` finds who can craft an item.
- `/ame status` shows your data and sync status.
- `/ame config` opens the settings.
- `/ame selftest` checks that everything is working.
- `/ame help` lists the rest.

## Good to know

- AME only knows what has been scanned. Signals, sales per day and profits are estimates based on that data, not guarantees. You're always the one who decides what to buy.
- AME never scans on its own and needs no desktop app.
- Available in English, German, French, Spanish, Russian, Portuguese, Italian, Korean and Chinese (simplified and traditional).
- AME is in beta. Things may change between versions, and your feedback shapes what comes next.

## Feedback and source code

Found a bug or have an idea? Open an issue on GitHub: **https://github.com/Evanion/ame**

## License

AME is open source under the GNU LGPL v3.0 or later. The bundled chart library, LibAMEChart-1.0, is MIT licensed.
