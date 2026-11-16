# Azeroth Mercantile Exchange (AME): Design Draft

Status: draft v0 (2026-11-16). Working document; expect it to change as spikes land.

## Goal

An in-game addon for **WoW Forever** that records auction house prices over time, per realm and faction, and turns them into a "futures market" view:

- price and volume history charts;
- trend, volatility and mean-reversion signals;
- a screener that surfaces items you didn't know to look at.

It runs with **no external desktop app**, and **reuses Auctionator's scans** instead of running its own.

UX target: on par with the best current addons (TSM, Auctionator, Baganator-level polish).

## Verified facts (checked against the local install)

Install path: `C:\Games\World of Warcraft\_forever_\` (flavor `wowf`).

### Auctionator v347

- Its TOC lists Interface `120100, 120105, 16001, ...`, so one codebase covers every flavour.
- On Forever it uses the **modern AH** code path (`Source_ModernAH`).
- **Full scan** (`Source_ModernAH/FullScan/Mixins/Frame.lua`) calls `C_AuctionHouse.ReplicateItems()`, waits for `REPLICATE_ITEM_LIST_UPDATE`, then reads `C_AuctionHouse.GetNumReplicateItems()` and `GetReplicateItemInfo(i)`.
  - The replicate list is client-global, so our addon can register for the same event and read the same data **without an extra scan**. This is the core ingestion strategy and still needs an in-game spike.
- **Public API** (`Auctionator.API.v1.*`, every call takes a `callerID` first):
  - prices and ages: `GetAuctionPriceByItemID/Link`, `GetAuctionAgeByItemID/Link`, `IsAuctionDataExactByItemID/Link`;
  - vendor and disenchant: `GetVendorPrice*`, `GetDisenchantPrice*`;
  - search and shopping lists: `MultiSearch*`, shopping-list CRUD.
- `RegisterForDBUpdate(callerID, cb)` fires on `IncrementalScan.Events.PricesProcessed` and `FullScan.Events.ScanComplete`, with no payload.
- **Internal price DB** (`AUCTIONATOR_PRICE_DATABASE`):
  - per item, a daily low (`l[day]`) and high (`h[day]`);
  - pruned after `PRICE_HISTORY_DAYS` (default ~21);
  - **not exposed via the API**. We can backfill from it once, read-only and guarded, accepting that it may break.
- The local account-wide `Auctionator.lua` SavedVariables file is ~500 KB today.

### AHDB (AuctionDB v2.7.1, MooreaTV, LGPLv3)

- Already installed, with a WoW Forever edition. It does its own full scans and has history graphs on Alt-click.
- It is the closest competitor and a useful reference for an open-source approach.
- It keeps every scan for about 2 days, then daily summaries for 180 days.

## External findings (research, 2026-11-16)

- **Charting:** LibGraph-2.0 (last release Dec 2022) is the only reusable library, and it's dated. Serious addons (AHDB, AzerothCharts) hand-roll their charts. → **We build a reusable chart library.**
- **Standard stack:**
  - LibStub;
  - Ace3 (AceAddon, AceEvent, AceTimer, AceConsole, AceDB, AceConfig/AceConfigDialog, AceComm + ChatThrottleLib for sync);
  - CallbackHandler-1.0;
  - LibDataBroker-1.1 + LibDBIcon-1.0;
  - LibSharedMedia-3.0;
  - LibSerialize + LibDeflate for compression. LibSerialize by rossnichols has async (yielding) modes; beware the abandoned CurseForge namesake.
- **AceGUI** is fine for options. Main windows in top addons are custom-built.
- **SavedVariables:**
  - There's no documented hard cap. The real cost is the **full parse at login**.
  - Auctioneer died of tens-of-MB files.
  - Whitespace and table nesting matter: AllTheThings saved ~4 s by shrinking 4.5 → 2.1 MB.
- **WoW Forever beta** had a SavedVariables-not-loading bug, reportedly fixed in 1.60.1. → We ship export/backup.
- **TSM:** there's no confirmation it runs on Forever. Even where it does, TSM has no public way for third-party addons to register price sources. → **Deferred**: at most an optional read-only adapter via `TSM_API` later.
- **AzerothCharts** is a Forever-only competitor (All Rights Reserved) with tooltip mini-charts.

## Architecture

### Packages (each is its own addon folder in this repo)

| Folder | Role | Load |
|---|---|---|
| `AzerothMercantileExchange` | Core: ingestion, analytics, UI, slash `/ame` | always |
| `AzerothMercantileExchange_History` | History store (SavedVariables only + codec) | on demand: at AH open, or when UI needs history |
| `Lib<Chart>` (name TBD) | Standalone, embeddable time-series chart library | embedded via LibStub, also published separately |
| `Lib<TimeSeries>` (maybe) | Columnar rollup store + codec, if it turns out generic enough | embedded |

Splitting the history into a load-on-demand addon keeps login fast: its SavedVariables are only parsed when it loads.

### Shards

- **Shard key** = normalized realm + **house**. House is `Alliance`, `Horde` or `Neutral` (goblin AH).
  - Detect it at `AUCTION_HOUSE_SHOW` via `UnitFactionGroup("npc") or "Neutral"`. This is the same technique AHDB uses on Forever.
  - So a Horde character at the goblin AH writes to the `Neutral` shard, not `Horde`.
  - The UI defaults to the last-visited house, falling back to the player's faction.
- Only the current shard is decoded in memory. Other shards stay as compressed strings, which parse quickly as single string literals.
- To verify on Forever: do connected realms share an AH? If so, the realm part of the key should be the connected-realm group.

### Data model (per shard, per item key)

- Item key: `itemID` (+ suffix or item level where relevant, mirroring Auctionator's key logic).
- Prices are integers in copper.
- Storage is **columnar arrays**, not tables per sample.

| Tier | Resolution | Fields | Retention (default) |
|---|---|---|---|
| raw | every scan | t, min, p25 ("market"), median, quantity, auctions | 48 h |
| daily | 1/day | min, market, median, max, avg qty, scans | 180 d |
| weekly | 1/week | same as daily | forever (compressed) |

- Rollups run incrementally, batched over frames.
- Cold tiers are packed with LibSerialize + LibDeflate and decoded only when an item is viewed.

### Ingestion

1. **Full scan piggyback (primary).**
   - Listen for `REPLICATE_ITEM_LIST_UPDATE` (Auctionator triggers the scan).
   - Read all replicate rows in a coroutine, aggregate per item, then commit a snapshot.
   - Must handle item info that isn't loaded yet (Auctionator waits on item data; we key by itemID so we may not need to).
2. **Search results (secondary).**
   - `COMMODITY_SEARCH_RESULTS_UPDATED` / `ITEM_SEARCH_RESULTS_UPDATED` give the **full order book** for items browsed or searched.
   - That means depth, not just the minimum.
3. **Auctionator `RegisterForDBUpdate`.** A fallback trigger; it also drives a refresh of the open UI.
4. **One-time backfill** from `AUCTIONATOR_PRICE_DATABASE` daily lows and highs, so charts aren't empty on day one.

### Analytics ("futures market")

- **Market value:** quantity-weighted, trimmed low percentile (TSM-style).
- **Moving averages:** SMA and EMA over 7, 14 and 30 days; momentum (rate of change); MACD-style crossovers.
- **Volatility:** standard deviation of log returns; z-score vs the 30-day mean (mean reversion); Bollinger-style bands.
- **Supply:** quantity trend, days of supply, listing churn.
- **Seasonality:** weekday and reset patterns (Tuesday reset, patch and phase days).
- **Opportunity score:** a composite ranked in a **screener** (filterable by category, price band and liquidity).

### UI

- **Main window:** custom frame, resizable, ElvUI/skin-friendly. Tabs:
  - **Market:** movers, screener, heat map by category.
  - **Item:** price + volume chart with overlays, stats panel, time-range zoom.
  - **Watchlist / Portfolio:** track positions and P&L later, from purchase and sale events plus mail.
  - **Settings:** AceConfig.
- **Tooltip:** sparkline + key stats.
- **Hooks:** Alt-click or right-click from AH, bags (Baganator) and Auctionator results.
- **Minimap and broker** via LibDBIcon / LibDataBroker.
- **Export/backup:** a copyable compressed string per shard, with import.

### Sync (sharing scans with other AME users)

Goal: when a guildmate (or a trusted friend or alt) scans, everyone gets the data without scanning themselves.

**Transport constraints:**
- `C_ChatInfo.SendAddonMessage` carries at most 255 bytes per message and is throttled per prefix.
- AHDB sends 230-byte parts at a 0.25 s spacing and backs off 1 s on `AddonMessageThrottle`. Realistic sustained throughput is around 0.5–1 KB/s, shared with every other addon.
- Whispers don't cross factions.
- `GUILD` messages reach all online members at once, so one broadcast serves everybody.

**Protocol sketch** (pull-based, gossip-style; never stream whole scans unprompted):
1. **Announce** (tiny, on `GUILD` / group): "I hold shard S, snapshots up to T, digest D". Sent on login, after a scan and on AH open.
2. **Reconcile:** peers compare announcements with their own state. Anyone behind sends a request naming the shard and the range it's missing.
   - One **responder is elected**: the most recent scanner, with ties broken by name. This avoids a reply storm.
   - The responder **broadcasts once** on `GUILD` if several peers are behind, otherwise it whispers.
3. **Payload:**
   - Per-scan or daily **summaries** (market, min, quantity per item), never raw listings.
   - Delta-encoded against the previous snapshot, then LibSerialize → LibDeflate → `EncodeForWoWAddonChannel`.
   - Chunking and throttling via AceComm + ChatThrottleLib at `BULK` priority, so we never disconnect anyone or starve boss-mod and raid traffic.
   - Transfers pause in combat and in instances.
   - Back-of-envelope: ~15k items × ~10 B compressed ≈ 150 KB per full snapshot (a few minutes). Daily deltas are much smaller.
4. **Lazy deep history:** when you open an item's chart and a peer has older history than you, ask for just that item (like AHDB's per-item `Q`/`H` queries).
5. **Scopes:**
   - **Guild** (default on);
   - **trusted list** (alts and friends; whisper-based, works cross-realm within faction; needs mutual opt-in, like `/ahdb trust`);
   - party/raid;
   - optional later: a hidden custom channel for server-wide sharing (opt-in, faction-limited, highest abuse risk).

**Trust and data integrity** (a shared market feed is a manipulation target):
- Each sample keeps its **provenance** (scanner and server time). Received data never overwrites your own observations.
- The aggregated price is the **median across sources**. Samples that disagree strongly with your own data or with other sources are flagged or dropped.
- Per-sender reputation and a block list. The UI shows "from your scan / from 3 guildmates".
- Dedupe: snapshot id = scanner + server time. Messages are versioned (`proto=1`) so older clients ignore what they don't understand.

**Possible interop later:** AHDB's protocol is documented in its LGPL `Comm.lua` (prefix `AHDB`, trusted whispers only). We could optionally speak it to receive data from AHDB users.

### Engineering

- Lua 5.1 (WoW). Pure logic (store, rollups, analytics, codec) is kept free of WoW API calls so it can be **unit-tested outside the game with busted**. TDD for all of it.
- `luacheck` with WoW globals.
- Packaging via the BigWigsMods packager (`.pkgmeta`) with libraries fetched as externals. GitHub Actions for lint, tests and releases (CurseForge, Wago, WoWInterface).
- Dev loop: directory junctions from `_forever_\Interface\AddOns\<Addon>` into this repo, then `/reload`.

## Milestones

- **M0 (spike, needs in-game test).**
  - A throwaway addon that, when an Auctionator full scan completes, reads the replicate list itself and prints row count, unique items and elapsed time.
  - Also confirm the shard key behaviour and measure SavedVariables write/load of one snapshot.
- **M1:** history store, codec, rollups and ingestion (busted-tested), plus Auctionator backfill.
- **M2:** chart library (line, area and volume bars; crosshair; zoom/pan; frame pooling) with a demo/test harness.
- **M3:** item window, tooltip sparkline and AH/bag hooks.
- **M4:** analytics engine and screener.
- **M5:** polish, export/backup, settings, packaging and first release.
- **M6:** sync.
  - Guild announce/reconcile, then the trusted list and lazy per-item history, then provenance and outlier handling.
  - The data model carries provenance from M1 so sync isn't a retrofit.

## Open questions

- Chart library name (it should be generic, e.g. `LibTimeSeriesChart-1.0`; check for name clashes).
- License: LGPL like AHDB, or MIT?
- Should the repo be public on GitHub from the start?
- How much of `GetReplicateItemInfo` data is complete on Forever (owner, quantity, buyout vs bid-only)?
- Sync: real addon-message throughput on Forever (measure in M0 with two characters or a guildmate). Should a server-wide hidden channel be offered at all?
