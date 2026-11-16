# Roadmap

Ship features in vertical slices. Each milestone ends with a single in-game command (`/ame selftest` or similar) that verifies it. Minor issues go to GitHub issues, not into the milestone.

| Milestone | Delivers | Status |
|---|---|---|
| M0 | Spike: scan piggyback, shard detection, storage and comms numbers | done |
| M1 | History store; ingestion of full scans and search/sell-tab results; Auctionator backfill; LoD history addon; `/ame selftest` | in progress |
| M2 | `LibAMEChart-1.0`, a reusable MIT time-series chart library: line/area/volume series, time axis, crosshair, hover tooltip, zoom/pan, frame pooling | |
| M3 | Item window (chart + stats + range buttons); Alt-click items to open; tooltip lines (market, 7d change, supply) | |
| M4 | Analytics (SMA/EMA, volatility, z-score, momentum, supply trend, opportunity score) and the Market screener tab | |
| M5 | Polish: settings (AceConfig), minimap button (LibDBIcon), export/backup, skins, packaging and first release | |
| M6 | Guild and trusted-list sync (announce/reconcile, paced, acked) | |

## Library stack (embedded under `Libs/`, fetched by `scripts/fetch-libs.sh` and by the packager)

- **LibStub, CallbackHandler-1.0** (from the Ace3 repo).
- **LibDeflate**: compression of history segments.
- **Ace3 modules** from M5 for settings. LibDataBroker and LibDBIcon from M5.

## Working rules

- Pure logic lives in `Core/*.lua` with busted specs. WoW glue is thin and verified with one in-game self-test per milestone.
- Every commit passes `stylua --check`, `luacheck` and `busted`.
