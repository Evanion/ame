# In-game test playbook

The addon is linked into `C:\Games\World of Warcraft\_forever_\Interface\AddOns\` through directory junctions:
- `AzerothMercantileExchange` points to the repo root.
- `AzerothMercantileExchange_History` points to the repo's history addon folder.

Edits in the repo are live after `/reload`. The M0 spike (`AME_Spike`) is no longer linked.

## Playbook (≈ 5-20 min; replicate-style full scans have a 15-minute server cooldown)

1. Log in. Make sure **Azeroth Mercantile Exchange** (and its History module, which loads on demand) is enabled.
2. Open the auction house and run a **full scan** with your scanning addon (e.g. Auctionator's Full Scan), or browse
   the auction house with an empty search to the end.
   - AME says `reading full scan (N listings)...`, then `recorded full scan: N items ...`.
   - If Auctionator is installed, the first visit to your faction's AH also imports its recent history
     ("imported N days ...").
3. Type **`/ame selftest`**. It runs every check, prints PASS/WARN/FAIL lines, then shows a **Reload UI** popup: click it so the results and timings reach `AME_DB` on disk (the game blocks addons from reloading on their own).

That's it. Claude reads the results from
`WTF\Account\<ACCOUNT>\SavedVariables\AzerothMercantileExchange.lua` (`AME_DB.selftest`, `AME_DB.stats`).

## Things to look at while you're there

- **`/ame`** opens the window.
  - The **Market** tab is the screener: sortable columns, Buy/Sell filters, click a row to chart it.
  - The **Item** tab shows the chart, stat cards and range buttons. Mouse wheel zooms, drag pans, double-click resets.
- **Alt-click** an item in your bags, a chat link or the AH to open its chart. Change it to Alt+Shift in `/ame config` if AHDB's Alt-click gets in the way.
- **Tooltips** show "AME market / average (7 days by default; Settings) / supply / signal" once the market index has been built (a few seconds after login or after a scan).
- **Guild sync** is on by default. `/ame status` shows announce/serve/receive counters.
- Check **BugSack** for errors.

## Known gaps

See GitHub issues. Notable ones:
- Cold chart loads take ~3 ms per day of history.
- Item variants (suffix and item level) share one series.
- LibDBIcon comes from the WowAce SVN: run `scripts/fetch-libs.sh` in a dev checkout (release builds include it).
- AME listens to the native auction house APIs, so full scans are picked up whichever addon (or the default UI)
  starts them. Replicate-style scans share the game's one-per-15-minutes limit across addons.
