# M1: History store, ingestion and backfill

Goal: every Auctionator full scan ends up in a compact, per-shard price history that survives reloads, loads fast, and can answer three questions cheaply:
- "give me item X's series" (charts, tooltips);
- "give me everyone's latest stats" (screener);
- "what's new since T" (sync, M6).

## Decisions (from M0 numbers)

**Shard** = `realm + "|" + house` (`Alliance` / `Horde` / `Neutral`).

**Item key** = `itemID` for M1. 6,451 itemIDs vs ~16k link variants.
- Variants (suffix and item level) are a later, additive tier. They need item data loaded; itemID prices are present at the first event.

**Per-item scan stats** (pure, from the listings in one scan):
- `min`: lowest unit buyout.
- `market`: quantity-weighted mean of the cheapest supply.
  - Always take the cheapest 15% of quantity.
  - Keep taking up to 30% while each unit price is ≤ 1.2× the previous one.
  - Then drop included listings outside [0.5×, 1.5×] of that mean (a lone undercut or a wishful tail) and recompute.
  - This is TSM-like, so a single cheap undercut doesn't define the price.
- `median`: quantity-weighted median unit price.
- `qty`: total units listed.
- `auctions`: listing count.

Prices are integer copper. Bid-only listings (no buyout) are skipped and counted.

**Store as built (tasks 4–7; supersedes the tier table below where they differ):**
- **Layout.** `days[day][bucket]` and `weeks[week][bucket]` hold packed segments, with 32 buckets by `itemID % 32`.
  - Day-major segments are written once per day and never rewritten after the day.
  - A lookup decompresses about 1/32 of history. That's about the same number of bytes as an item-major layout, without rewriting history every day.
- **Running sums.** Segments store running **sums** (market, median, qty, auctions), the min, and the scan count. Merging a scan is an incremental add.
  - Closed days never need their raw scans.
  - Late arrivals (sync) merge exactly.
  - `seen[day]` dedupes scans by time, source, kind and content shape.
- **One sample per item per hour.** An `hours` bitmask per item per day enforces it.
  - Repeated searches or sell-tab rechecks of the same items update `Latest`, and can lower the day's `min`, but don't skew daily means.
  - Full and partial scans (`kind`) are treated alike. A full scan covers every item.
- **Time slicing.** An injected `yield` is called between buckets, so ingest can time-slice inside a coroutine.
- **Benchmark** (plain Lua 5.1, identity compressor, 6,451 items, `bench/store_bench.lua`):
  - full-scan merge: 75 ms average, 196 ms worst (so it must be time-sliced);
  - partial: 1.3 ms;
  - `Series`: 16 ms cold, 0.06 ms warm.
- **`Summary` is moved to M4 (analytics).** M1 provides `Latest` and `Series`.

**Tiers:**

| Tier | Layout | Content | Retention |
|---|---|---|---|
| `raw` | one entry per scan (scan-major), compressed string | all item stats + `t` + `src` (provenance) | 48 h |
| `days` | 64 buckets by `itemID % 64`, item-major, compressed string per bucket | per item: daily points (`day, min, market, median, qty, auctions, scans`) | 180 d, then weekly |
| `weeks` | same buckets | weekly points | forever |
| `summary` | one compressed string per shard | per item: latest stats + a few precomputed indicators for tooltips/screener | rebuilt on rollup |

- **Item-major buckets** make an item lookup decode about 1/64 of the history (~100 items). An in-memory LRU of decoded buckets keeps tooltip hovers cheap.
- Decoding all of history at once would be ~6.4k items × 180 d × 6 fields ≈ 7M Lua numbers. Too much memory, so we never do it.

**Codec.** Columns → compact base-36 text with delta-encoded itemIDs, versioned (`1|...`).
- Then LibDeflate `CompressDeflate` + `EncodeForPrint` for SavedVariables safety.
- The compressor is injected, so the codec is testable without the library.

**Persistence.**
- `AzerothMercantileExchange_History` is a load-on-demand addon that owns `AME_HistoryDB`. It's loaded at AH open, or when the UI first needs history.
- Only the current shard is decoded. Other shards stay as strings.

**Ingestion.**
- `hooksecurefunc(C_AuctionHouse, "ReplicateItems")` marks scan start.
- The first `REPLICATE_ITEM_LIST_UPDATE` triggers one time-budgeted read (~8 ms/frame).
- Then stats → raw tier → rollup.
- All other replicate events are ignored. `AUCTION_HOUSE_CLOSED` (fires twice) is idempotent.

**Backfill.** One-time, read-only import of Auctionator's `AUCTIONATOR_PRICE_DATABASE` daily low/high into `days`, marked `src = "auctionator"`. It's guarded by `pcall` and a shape check, because it reads Auctionator's internals.

## Code layout

```
AzerothMercantileExchange.toc          core addon (repo root is the addon; packager convention)
Core/Init.lua                          namespace, version, constants
Core/Stats.lua                         pure: listings -> per-item stats         (busted)
Core/Codec.lua                         pure: columns <-> compact string         (busted)
Core/Store.lua                         pure: tiers, rollup, retention, queries  (busted, injected clock)
Core/Ingest.lua                        WoW: scan hook + budgeted reader          (busted with fake C_AuctionHouse)
Core/Backfill.lua                      pure transform of Auctionator's DB       (busted with fixture)
Core/Main.lua                          WoW wiring, slash /ame (debug dump in M1)
AzerothMercantileExchange_History/     LoD addon: TOC + SavedVariables only
embeds.xml, Libs/                      LibStub, CallbackHandler, Ace3 subset, LibDeflate (fetched, gitignored)
spec/                                  busted specs; spec/helpers/addon.lua loads files with (addonName, ns)
```

Pure modules take everything they need as arguments (clock, compressor, data). They never touch WoW globals.

## Tasks (each one test-first)

1. Layout, spec loader and TOC skeletons. Specs can load addon files with a namespace.
2. `Stats`: min, market, median, qty, auctions; edge cases (single listing, bid-only, zero count, undercut outlier, huge stacks).
3. `Codec`: round trip, delta ids, version check, empty snapshot, large values (> 2^31 copper), corrupted input → error, not garbage.
4. `Store` raw tier: add a snapshot with provenance; 48 h retention with an injected clock.
5. `Store` rollup: raw → daily points in item-major buckets; idempotent per day; multiple scans per day aggregate correctly.
6. `Store` queries: `Series(itemID, from, to)`, `Latest(itemID)`, `Summary()`; bucket LRU.
7. `Store` weekly compaction after 180 d.
8. `Ingest`: one read per `ReplicateItems` request; time-budgeted batches; ignores the event storm; handles AH closing mid-read.
9. `Backfill`: fixture from the real `AUCTIONATOR_PRICE_DATABASE` shape.
10. Wiring: TOCs, embeds, `.pkgmeta`, `/ame item <id|link>` debug dump, LoD history addon. Then an in-game verification run on a real scan.

**Done when:**
- all specs pass in CI;
- an Auctionator full scan in game produces a raw snapshot and today's daily points;
- `/ame item <link>` prints that item's history;
- `/reload` keeps it;
- login cost from `AME_HistoryDB` stays out of login, because the addon is LoD.
