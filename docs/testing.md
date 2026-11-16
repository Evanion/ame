# In-game test playbook

The addon is linked into `C:\Games\World of Warcraft\_forever_\Interface\AddOns\` through directory junctions:
- `AzerothMercantileExchange` points to the repo root.
- `AzerothMercantileExchange_History` points to the repo's history addon folder.

Edits in the repo are live after `/reload`. The M0 spike (`AME_Spike`) is no longer linked.

## Playbook (≈ 20 min, mostly waiting for Auctionator's scan cooldown)

1. Log in. Make sure **Azeroth Mercantile Exchange** (and its History module, which loads on demand) is enabled.
2. Open the auction house and run an **Auctionator full scan**.
   - Wait for `AME recorded full scan: N items ...` in chat. That's about 25 s after Auctionator's own message.
   - The first time you open the AH, AME also imports Auctionator's recent history ("imported N days ...").
3. Type **`/ame selftest`**. It runs every check, prints PASS/WARN/FAIL lines, then shows a **Reload UI** popup: click it so the results and timings reach `AME_DB` on disk (the game blocks addons from reloading on their own).

That's it. Claude reads the results from
`WTF\Account\<ACCOUNT>\SavedVariables\AzerothMercantileExchange.lua` (`AME_DB.selftest`, `AME_DB.stats`).

## Things to look at while you're there

- **`/ame`** opens the window.
  - The **Market** tab is the screener: sortable columns, Buy/Sell filters, click a row to chart it.
  - The **Item** tab shows the chart, stat cards and range buttons. Mouse wheel zooms, drag pans, double-click resets.
- **Alt-click** an item in your bags, a chat link or the AH to open its chart. Change it to Alt+Shift in `/ame config` if AHDB's Alt-click gets in the way.
- **Tooltips** show "AME market / 30d avg / supply / signal" once the market index has been built (a few seconds after login or after a scan).
- **Guild sync** is on by default. `/ame status` shows announce/serve/receive counters.
- Check **BugSack** for errors.

## Known gaps

See GitHub issues. Notable ones:
- Cold chart loads take ~3 ms per day of history.
- Item variants (suffix and item level) share one series.
- LibDBIcon isn't embedded in dev builds; the minimap button appears only if another addon loaded LibDBIcon.
