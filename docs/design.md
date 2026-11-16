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

## M0 spike results (run 1, 2026-11-16, Horde AH, realm `CAMWOWEU5Realm6PvP`)

**Piggyback works.** We read Auctionator's full scan with no scan of our own.

**Scan size.** 193,961 rows, 6,446 unique itemIDs, ~15.9k unique item links (suffix and item-level variants).
- Only 2 rows were bid-only (no buyout).
- Every item had a buyout price.

**Read cost.** One full read takes 7.5–10 s wall time at 1,000 rows per frame. The worst frame is 11–14 ms, so there's no visible hitch.

**Event storm.** `REPLICATE_ITEM_LIST_UPDATE` fired **291,250 times** in 66 s, roughly once per row as item data loads, and kept firing until the AH closed.
- Production must read **once per `ReplicateItems()` request**: `hooksecurefunc(C_AuctionHouse, "ReplicateItems", ...)` marks scan start, then the first event triggers the read.
- Never do per-event work.
- v1 of the spike re-read 7 times and logged every event; that log made up most of the 27.8 MB file.

**Incomplete rows.** ~25% of rows (48–52k) report `hasAllInfo = false` at read time.
- Spike v2 checks whether buyout and count are still present on those rows. The v1 aggregate suggests yes, since we got no missing prices.
- If so, keying by itemID needs no item-data loading. Variant keys (links) need it.

**Auctionator callback.** `RegisterForDBUpdate` fired about 11 s after the first replicate event, once Auctionator finished processing.

**Shard.** Horde AH (`UnitFactionGroup("npc")`). `GetAutoCompleteRealms()` returned no connected realms. The Neutral AH is not tested yet.

**SavedVariables.** A 27.8 MB file (30 stress snapshots plus a 291k-entry log) took about 289 ms between our file loading and `ADDON_LOADED`, roughly 10 ms/MB.
- WoW writes arrays as `value, -- [n]` lines, which is very verbose.
- This confirms the plan: pack history into compressed strings, and size it per snapshot in run 2.

**Comms.** Whispering `Name-NormalizedRealm` to yourself failed with "No player named … is online". Spike v2 uses the plain name.
- All 200 sends returned Success within 3 ms with no throttle result. The client accepted them instantly.
- So real throughput must be measured on the **receiving** side, not from send results.

## M0 spike results (run 2, 2026-11-16, Horde AH)

**Scan-start hook works.** `hooksecurefunc(C_AuctionHouse, "ReplicateItems", ...)` fired, and the first `REPLICATE_ITEM_LIST_UPDATE` arrived **16.5 s** later (server latency).
- 198,643 rows, 6,451 itemIDs, read in 9.4 s, worst frame 11 ms.

**Prices are present on incomplete rows.** Of 51,419 rows with `hasAllInfo = false`, **51,417 still had buyout and count**.
- → Keying by itemID needs **no item-data loading**, so ingestion can start at the first event.
- A re-read 30 s later found the same items. More links had resolved by then (15,862 → 16,130), which matters only for variant keys.

**Event storm confirmed.** 66,090 events in the first 30 s and 99,468 in total. `AUCTION_HOUSE_CLOSED` arrives **twice** per close.

**Auctionator `RegisterForDBUpdate` fires often:** after the full scan and after every normal browse or search (incremental scans). It's useful as a "prices changed, refresh UI" signal, but it can't mark a full scan.

**Storage per snapshot** (6,451 items × itemID/minUnit/qty/rows), measured offline from the saved data:

| Encoding | Bytes per snapshot | Bytes per item | 180 daily snapshots |
|---|---|---|---|
| WoW SavedVariables tables | 130 KB | 20.2 | ~23 MB (slow login) |
| compact string (sorted, delta itemIDs) | 64 KB | 10.0 | ~11.6 MB |
| compact + deflate (gzip -9 as a proxy) | **23.5 KB** | **3.7** | **~4.2 MB** (~5.6 MB after print-safe encoding) |

- Deltas *between* days should shrink this further.
- **Decision for M1: cold history is stored as compressed strings.**
- Load cost observed: a 27.8 MB table-format file took ~272–289 ms before `ADDON_LOADED`.

## M0 spike results (comms, 2026-11-16)

**Character names on Forever are "First Last"** (the sender showed as `Tyken Evanion`). AHDB's `/ahdb trust <First Last>` reflects the same thing.
- Whisper targets and trust lists must use the full name. `Name-Realm` and the bare first name both failed.

**Unpaced burst of 50:** the client returned Success for all 50 within 1 ms, with no throttle result. The receiver got exactly **10 of 50**, within 1 ms.
- → This matches a server-side burst allowance of ~10 messages per prefix. The excess is **dropped silently**, and the sender can't tell.

**Paced at 0.25 s (20 messages):** nothing was received. Self-whispers to the first name only are not a reliable test.
- The 10 that did arrive were labelled with channel `GUILD`, which is unexplained.

**Correction and guild result:** the "10 of 50" above was most likely the **guild** burst. The spike merged streams per sender across channels; that's now fixed.
**Guild run (11:12–11:13 UTC).** A burst of 50 and a paced run of 20 (0.25 s) ran **concurrently** on the same prefix.
- Their receive streams interleaved: they were received as 28/50 and 20/20, so the per-stream receive counts are not reliable.

**The send side is clear: a client-side throttle exists for `GUILD`.** `SendAddonMessage` returned `AddonMessageThrottle` 863 times (401 + 462, retried every 0.1 s).
- The two streams together pushed 70 messages in ~59 s.
- That fits **a burst of ~10 messages, then ~1 message/s per prefix**: 10 + 59 ≈ 70.
- → Sustained throughput is **~255 B/s per prefix**.

**Sizing.** One compressed daily snapshot (~23.5 KB) ≈ **95 s** of guild traffic; daily deltas are less.
- Bulk sync is feasible if paced at the throttle rate and run in the background.
- Using multiple prefixes to go faster is possible but antisocial; don't.

**Behaviour difference.** The unpaced self-whisper burst got `Success` for all 50 but delivered 10. `GUILD` reports throttling properly.
- → Treat `Success` as "maybe" on `WHISPER`; acks are required there.

**Takeaways for sync (M6):**
- Never rely on send results. Use receiver acks, sequence numbers and resend requests.
- Pace conservatively.
- Measure real throughput with two clients (a second account or a guildmate) during M6.

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
   - Measured in M0: 6.4k items ≈ 23.5 KB compressed per snapshot. At the measured ~255 B/s guild throttle that's ≈ 95 s. Daily deltas are much smaller.
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
