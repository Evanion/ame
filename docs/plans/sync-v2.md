# Sync v2: guild fan-out, resumable transfers, a 7-day window

Status: agreed (Nov 2026). Step 1 built; steps 2-7 to do.

### As built

- **Step 1.** `data.hours` in Core/Store.lua:
  - `AddHourFrom`, `HourPoint`, `Store.ScanKey`; `Codec.HOUR_FIELDS` and `Codec.Round3`.
  - The item chart's 7D range plots hourly points, with 6-hour candles. It shows the daily points while they load.
  - Upgrading: a full scan from before hourly points existed leaves its hour when it's pruned at 48 h.
  - The late-merge sell-rate pair fix moved to step 3: until sync delivers points, every point comes from a scan
    that was already merged.
- **Measured on the real history:**
  - A stored point is ~40 KB, not 26 KB: the store compresses in 16 KB pieces (Compress.CHUNK) to avoid frame
    hitches.
  - Building one takes ~50 ms; reading one ~20 ms (in a background job, which pauses between steps).
  - Sync (step 2) should send a one-piece compression of the point, built in the background.

## Why

Sync v1 (Core/Sync.lua, Core/SyncService.lua) has three problems.

**Each scan is one large whispered message.**
- A full scan is now 150-260 KB, about 6x more than before. Random-suffix variants count as their own items since
  0.3.0: ~25k item keys instead of ~6.8k.
- AceComm splits each scan into a few hundred 255-byte parts. Losing any one of them (a disconnect, `/reload`, logging
  off, or the burst limit silently dropping whispers, see design.md) loses the whole scan.
- The scan is then requested again from zero, after a 10-minute cooldown.

**The same bytes go out once per guildmate.** Every requester is whispered its own copy, so five guildmates
missing a scan cost five copies.

**Only the last 48 hours sync.** Raw scans are kept for RAW_KEEP = 48 h, so nothing older can be served.

The goal: each player has, for each house, at least one point per hour that anyone in the guild scanned, for the
last 7 days. That data feeds both the item chart (hourly points) and analytics (sell rate, trends, volatility).

## Constraints (measured)

**Bandwidth** (design.md, "M0 spike results (comms)"):
- A burst of ~10 messages, then ~1 message/s per prefix, per sender: **~255 B/s**, whether to the guild or in whispers.
- Whispers beyond the burst are dropped silently, and the send call still reports Success. So delivery needs
  acknowledgements and resend requests, not send results.

**Data sizes**, from a real Horde-AH history (Nov 18-20, 18 full scans). Compressed and print-safe, as sent:

| What | Size | Time at 255 B/s |
|---|---|---|
| Full scan, as stored today (6 fields, all ~25k keys) | 190-260 KB | 12-17 min |
| Plain items only (~6.5k), 4 fields, prices to 3 significant figures | ~26 KB | ~100 s |
| Variants only (~19k), same encoding | 90-125 KB | 6-8 min |
| Plain-item delta vs a scan 35-50 min earlier | 19-23 KB | ~80 s |
| Plain-item delta vs a scan 3-10 min earlier | 12-16 KB | ~55 s |
| One stored day (all items, with sell-rate data) | ~80 KB | ~5 min |

Two conclusions follow:
- **Deltas between hours save little.** Within an hour, most plain items change their lowest price, market price or
  quantity. Hourly points therefore go out whole (a "keyframe"), not as deltas.
- **Hourly variant data is too expensive.** At 6-8 minutes per hour, a week of variant hours would take about 20
  hours of sending. Variants get daily points only, which the stored days already carry.

**Coverage.** The guild makes about 9 full scans a day. "Hourly" means every hour someone scanned, not 24 points a day.

## Design

### Protocol and the setting

- v2 uses its own addon prefix, `AME2`. v1 stays on `AME1`, unchanged.
  - design.md warns against extra prefixes to get more bandwidth. This isn't that: v2 replaces v1 traffic rather than
    adding to it.
- **Setting** "Sync protocol", in Settings > Sharing: **v2** (default) or **v1 (lighter)**.
  - On v1 the player doesn't register `AME2`, so the game never delivers them v2 traffic.
  - It's the answer to "sync slows my game": switch to v1.
- **v2 players also speak v1.** They answer v1 requests over whispers. They also send the v1 announcement, but only
  while a v1 player has been heard in the last 3 days, so a guild that's all on v2 pays nothing for it.
- **v1 is never removed:** it's the fallback.
- Trusted players outside the guild can't hear the guild channel. With them, v2 sends the same messages by whisper.

### Hourly points

- After each full scan, the store also derives an **hourly point** for that house and UTC hour, kept in a new
  `data.hours` tier.
  - Contents: plain items only; fields ids, min, market, qty, auctions; min and market rounded to 3 significant
    figures.
  - Identity: the dedupe key of the scan it came from, so a point and its scan are never counted twice.
- One point per house per hour. If an hour has several scans, the newest wins.
- Kept for 7 days. This replaces raw scans as the source for intraday charts beyond the 48 h raw tier.
- Size: 168 points × ~26 KB ≈ 4.4 MB per busy house, at most. Loading costs about 10 ms per MB, so about 45 ms.

**Merging a point that arrives late:**
- Day segments: merged like a scan, deduped by key.
- Sell rate: a point that lands between two that were already paired (A → C) replaces that pair with A → B and
  B → C. Day segments hold sums, so that's an exact subtract-and-add, using quantities from the hours tier.

### Transfers: blocks, manifests, fan-out

**Objects.** Three kinds: a full scan (whole, as today), an hourly point, and a stored day. Each has an ID: kind, house,
time, the dedupe key, total size and a checksum.

**Blocks.** Each object goes out in 240-byte blocks numbered 1..n, each a single addon message. No AceComm multipart:
losing one block loses only that block.

**Manifest.** Sent to the guild every 10 minutes, and on Sync now. For each house it lists:
- a 168-bit bitmap of the hours you hold a point for, plus each point's ID;
- the days you hold for the last 7 days.

**Push.** A new hourly point from your own scan goes to the guild immediately, at ~100 s each. Everyone online gets it
from that one send.

**Pull.**
- A player missing hours sends a request to the guild for those IDs, newest first.
- Each holder waits a random 0-3 s before answering, and stays quiet if it sees another holder's blocks for that
  object already arriving. That keeps it to one sender per object.
- Everyone else missing that object takes the same blocks, without asking.

**Missing blocks.**
- When blocks for an object stop arriving for 10 s, a receiver waits a random moment, then asks for the block
  numbers it lacks, as ranges.
- If it sees someone else ask for the same blocks first, it waits for that resend instead.
- Retries are capped. After that, the object is asked for again on the next manifest.

**Splitting the work.** When several players hold the same object, a request can name block ranges per holder, so
each sends a share at its own 255 B/s. Larger objects only (days, full scans).

**Resuming.** Received blocks are kept in memory, and saved for an hour, so `/reload` resumes a transfer.

**Stored days.**
- Sent only to players who hold no scan for that day. Their seen list for the day is empty, so the merge is exact
  without dedupe.
- This is how a new install or a returning player gets days 3-7 at full detail, variants and sell rate included.

**Full scans.** Pulled only for the newest hour, by players who want everything. Others stop at the hourly point.

**Priority.** Hourly points from the last 48 h first, then whole days, then older hours.

**Rough time for a returning player missing the full week, from one sender:**
- 48 hourly points at ~100 s each: about 80 minutes;
- 5 days at ~5 min each: about 25 minutes.

It's faster with several holders, and every other returning player gets the same transfer for free.

### Safety

- **Accepting unrequested data.** Guild objects no longer need a prior request. An object is accepted only when it:
  - matches an ID from a manifest by someone the trust rules allow;
  - passes its checksum;
  - passes `Sync.Plausible` against our prices, as today.
- **Blocked players' data** is never accepted; their requests are never answered.
- **Load limits:** at most one object sending at a time per player. In-flight block buffers are capped (memory).
  Instances and combat are not paused: ChatThrottleLib's BULK priority already yields to raid traffic.

## Steps

1. **Hourly points (store only).**
   - Add the `data.hours` tier: derived from full scans, kept 7 days.
   - Intraday chart reads it beyond 48 h; the late-merge pair fix for sell rate.
   - Specs. No protocol changes yet.
2. **Block layer (pure)**, in Core/SyncV2.lua:
   - object IDs, block cut and join, checksum, manifest encode/decode, request and missing-block messages;
   - the random-wait and stay-quiet decisions, as pure functions.
3. **Transport and service:**
   - the `AME2` prefix, a block pacer at BULK priority, receive buffers, resume across `/reload`;
   - push, pull, missing blocks, splitting between holders.
   - Specs with a simulated guild of 3-5 players, including dropped blocks.
4. **Stored days for empty days, and the 7-day window.**
5. **Protocol setting and v1 compatibility:** the setting, sending the v1 announcement only while v1 players are
   around, and an integration test with v1 and v2 players mixed.
6. **Visible to the player:**
   - Sharing status: hours held vs available, transfers in progress, the active protocol;
   - Guide (the Sharing article), changelog.
7. **In game:**
   - two or three guildmates on v2, one on v1;
   - check push, catch-up, `/reload` mid-transfer, and that sync stays smooth during instances and combat.

## Open questions

- Is 3 significant figures enough precision for posting suggestions? (Proposal: the hourly point feeds charts and
  analytics only; posting prices still come from your own and pushed scans.)
- Should the chart show variants hourly when your own scans have them? (Proposal: yes. Variants just don't sync hourly.)
- How long can a burst of guild traffic run before players notice lag? To measure during step 7.
