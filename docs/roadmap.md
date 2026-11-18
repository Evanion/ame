# Roadmap

Ship features in vertical slices: pure logic with busted specs, thin WoW glue, one integration spec per feature. Minor
issues go to GitHub issues, not into the milestone.

## Released

0.1.0 betas: M0-M6b. 0.2.0-beta.1: M7-M12. 0.2.0-beta.2: M14 (translations). In-game tested by the author.

| Milestone | Delivers | Status |
|---|---|---|
| M0 | Spike: scan piggyback, shard detection, storage and comms numbers | done |
| M1 | History store; ingestion of full scans (replicate, browse summary, getAll) and searches/browsing; Auctionator history import; LoD history addon; `/ame selftest` | done |
| M2 | `LibAMEChart-1.0` (MIT): line/area/volume/candle series, smooth curves, glow, gradients, value tags, crosshair, zoom/pan | done |
| M3 | Item tab: chart (2D intraday, 7D...All), candles with daily highs, stat cards, name search, Shift/Alt-click | done |
| M4 | Analytics (averages, volatility, z-score, trend, score, Buy/Hold/Sell, outlier filter) and the Market screener | done |
| M5 | Settings tab, themes, minimap/LDB launcher, packaging (`scripts/package.sh`) | done |
| M6 | Guild + trusted-player sync (relays, all houses, handshake, blocklists, poisoning check) | done |
| M6b | Watchlists + alerts; cross-AH Arbitrage with real cuts and deposits; AH search from AME | done |

## 0.2 milestones: what other AH addons don't do

Positioning (see the competitive review in the session notes): every addon shows prices; AME answers the trader's
questions behind them - can I sell it, how much can I buy before the edge is gone, what is my position worth, how
much should I trust this number, and what is my guild watching.

| Milestone | Delivers | Status |
|---|---|---|
| M7 | **Liquidity.** Estimated units sold per day from supply drain between consecutive full scans of the same house (sold + cancelled + expired, labelled as an estimate); days-to-sell for a stack. Screener column, item page, tooltip detail, Arbitrage sell-side liquidity. | built |
| M8 | **Market depth.** Keep the latest order book (price tiers) from item/commodity searches; cost of buying N units, and how many units an arbitrage route stays profitable for ("buy 37, +12g"). Searching from the Arbitrage tab fills it. | built |
| M9 | **Portfolio and ledger.** AH sales and purchases from auction mail invoices (net of cut and deposit); holdings in bags, bank and active auctions per character, account-wide; cost basis from purchases; unrealized and realized P&L; Portfolio tab with Buy/Hold/Sell next to each position. | built |
| M10 | **Data confidence.** Per item: scans in the last 7 days and freshness, shown as a confidence marker (high / medium / low) in the screener, item page and tooltip detail. | built |
| M11 | **Guild watchlists.** Share a watchlist with the guild over sync; members see it in the sidebar (read-only, copyable) as a guild market board. | built |
| M12 | **Price x supply phases.** Read price trend against supply trend (shortage, steady demand, sellers piling in, tightening, balanced, pressure building, sellers withdrawing, weak demand, dumping); show the phase and let it confirm or veto signals (a Buy while dumping becomes Wait). | built |
| M13 | **Posting price.** An adaptive queue model instead of 1c undercutting: units ahead at each price, sales rate, undercutting supply and undercut size per item (from consecutive scans, with a 5-band price ladder per scan), hour-of-day and weekday shapes, and calibration from your own posts (sold vs expired); items with little data borrow from their category. Expected value weighs the chance of selling against the deposit (1s minimum per post). Quick / Normal / Patient on the item page and a bar under the AH sell window that fills the price. | built |
| M14 | **Translations.** AceLocale; deDE, frFR, esES (+esMX), ruRU, ptBR, itIT, koKR, zhCN, zhTW (AI-made, for native review). | built |

M7-M12 shipped in 0.2.0-beta.1, M14 in 0.2.0-beta.2; M13 is built and not released yet.

## Maintenance (Nov 2026)

Performance and cleanup review: incremental market index rebuilds, smaller scan-storage frame spikes, history
retention (60 days daily, 52 weeks weekly), O(n) ledger profits, Settings / ItemCache out of UI, Window / Panels /
Main split per concern, errors reported instead of swallowed. Next: shared UI components (button groups, inputs,
cards, colours).

## M15: holistic redesign (built, awaiting in-game check)

Shared shell with resizable, dockable window and breakpoints; Item, sell bar, Market, Arbitrage, Portfolio, Settings,
Sync and guidance redesigned in phases P1-P9. Spec and plan: [docs/plans/m15-redesign.md](plans/m15-redesign.md). P1-P8 built with specs (Nov 2026); P9's
in-game check at both sizes and the release are next.

## Later

- Crafting margins (reagent cost vs product price), disenchant values, deal finder / sniper. Others
  (AHledger, TSM, AzerothCharts, Fojji) cover these; add them once AME's own strengths are in.
- Liquidity: tell sold from expired. Match individual auctions between replicate scans (gone with hours left =
  sold or cancelled; gone in its last "short" window = expired), weight browse-summary drains by price (cheap
  listings that vanish were bought), and use your own auction mail (exact) as a calibration.
- Posting price: pool listing outcomes over guild sync; a backtest of signals and posting advice once there are
  ~3 weeks of data (an offline script over AME_DB).
- Hourly history beyond 48 h; gear variants (#3); export (#6).

## Working rules

- Pure logic lives in `Core/*.lua` with busted specs. WoW glue is thin and covered by integration specs that load the
  real TOC in a stubbed client.
- Every commit passes `stylua --check`, `luacheck` and `busted`.
- User-facing text is scanner-agnostic: AME records through the game's native AH APIs (works with any scanner).
