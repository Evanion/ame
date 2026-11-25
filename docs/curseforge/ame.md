**Azeroth Mercantile Exchange (AME)** keeps a price history for everything you scan at the auction house, and uses it for charts, buy and sell signals and posting prices. It also tracks what you own on every character, compares the Alliance, Horde and goblin auction houses, and works out which of your recipes make money.

You scan or search the way you already do, with the default auction house or with Auctionator, and AME records it in the background. The longer you use it, the more history each item has.

## Market data

Every item gets a price and volume chart, built from your scans and your guild's. You can look at the last two days scan by scan, the last week hour by hour, or the item's whole history, as a line or as candlesticks, with MA 20 and the 7-day average on top. Hover a point to see its price and volume.

Each item also gets a signal. Buy, Hold and Sell compare today's price with the item's own history. Wait means sellers are dumping. Vendor means a vendor pays more than the auction house would after the cut, and DE means the item is worth more disenchanted.

AME also compares price with supply, so it can tell a real shortage from a flood of new listings, or a quiet market from someone dumping stock.

The screener lists everything on the auction house with these numbers attached. Filter by category, quality, price and signal, sort by any column, and save the views you use often.

Sales counts come from real auction outcomes, yours and your guild's, because a scan can't tell a sale from an expired listing. An item someone reposts every day without selling won't show up as a bestseller.

If you want the whole market at a glance, the optional overview has a market index, a CPI, turnover, and the day's biggest risers and fallers.

## Buying and selling

When you post, AME suggests a Quick, Normal and Patient price, based on the listings ahead of you, how fast the item sells and how often it gets undercut. A bar under the sell window fills the price in with one click.

If you don't use Auctionator, AME adds two tabs to the auction house. Shopping is a filtered search with signals on every result, your shopping lists, and a warning when a bulk buy will cost more than the listings on screen. Selling shows what in your bags is worth listing and posts it in one click.

Before you buy a lot of something, check roughly how many sell per day and how long your stack would take to move. AME also shows what buying 20 would cost across the listings, since the cheapest one rarely tells the whole story.

Shopping lists subtract what your characters already hold, cross off what you buy, and search the auction house for the rest. At a vendor that sells something on one of your lists, a panel next to the merchant buys the right amount.

To trade between auction houses, compare Alliance, Horde and goblin prices side by side. Profits are shown after the cut and deposit, with how many you can buy before the margin is gone ("buy 37, +12g").

## Crafting

Open each profession once per character and AME remembers the recipes. From there it ranks them by profit at current prices, tells you whether the materials you hold are worth more raw or crafted, and finds the cheapest way to reach a skill level you pick. It also lists recipes on the auction house that one of your characters could learn, ranked by how fast they pay back, and checks who in your guild already knows each one.

In the profession window you get the profit on every recipe and a craft queue. The queue makes the parts first, tells you where each material comes from (bags, bank, an alt, a guild bank, a vendor or the auction house), and has a Craft next button.

Need something made? Search an item or enchant to see which guildmates or trusted players can craft it, and whisper them with the recipe linked.

## Your gold and stock

AME reads your auction mail to log what you bought and sold, counts what you hold in bags, bank, mailbox and auctions on every character, and shows your profit or loss per item.

Item tooltips show the market price (each, and for everything you have), what you hold across characters and guild banks, the disenchant value, how fast it sells and its signal. Hold Shift for more.

Put the items you trade on a watchlist and AME can alert you when one crosses a price or turns Buy or Sell. Alerts collect under the bell in the AME window and on your info bar (LibDataBroker).

Every item has a high, medium or low confidence marker, depending on how much recent data AME has for it.

## Guild sharing

When a guildmate or trusted friend with AME scans, your prices update too, and if you were offline you catch up when you log in. You can share watchlists and shopping lists with the guild and see who crafts what.

Sync pauses in combat and doesn't freeze the game. Other players' data never overwrites your own, and suspicious prices are filtered out.

## Getting started

1. Install AME and log in. AME Crafting Data comes with it. It holds the recipe data and only loads when you open the Crafting tab.
2. Go to the auction house and scan or search as usual. AME works with the default auction house and with scanning addons like Auctionator. Without one, use the **Full scan** button AME adds to the auction house window.
3. Type `/ame` to open the exchange, or `/ame <item link>` to chart an item. You can also set a modifier click that opens any item's chart (Settings, General).
4. Open each of your professions once on every character, so AME knows what they can craft.

If you already use Auctionator, AME can import your existing price history the first time you run it, so your charts have data from day one.

Scanning more often gives you better charts and signals. Prices are tracked separately for each realm and each auction house.

The **Guide** tab in the AME window explains every feature and has a glossary of every number AME shows.

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

- AME only knows what has been scanned. Signals, sales per day and profits are estimates from that data. What you buy is still up to you.
- AME never scans on its own and doesn't need a desktop app.
- Available in English, German, French, Spanish, Russian, Portuguese, Italian, Korean and Chinese (simplified and traditional).
- AME is in beta, so expect things to change between versions.

## Feedback and source code

Bug reports and ideas go to GitHub: **https://github.com/Evanion/ame**

## License

AME is open source under the GNU LGPL v3.0 or later. The bundled chart library, LibAMEChart-1.0, is MIT licensed.
