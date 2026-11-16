# Azeroth Mercantile Exchange (AME)

A World of Warcraft: Forever addon that records auction house prices over time and turns them into a futures-market view: price and volume charts, trend and volatility signals, and a screener for items worth investing in.

- It records every scan and search through the game's native auction house APIs, so it works with the default
  auction house window and any scanning addon (it works well with addons like Auctionator). No extra scanning.
- Prices are kept separately per market (realm, or ruleset on Forever) and auction house (Alliance, Horde or goblin).
- Scans are shared with guildmates and trusted friends running AME.
- Optional: imports your existing Auctionator price history on first use.

**Status:** beta. See [docs/design.md](docs/design.md) and [docs/roadmap.md](docs/roadmap.md).

## Development

- Lua 5.1 (the WoW runtime).
- Tests: [busted](https://lunarmodules.github.io/busted/). Lint: luacheck. Formatting: StyLua.

```bash
luacheck . && busted && stylua --check .
```

During development, link an addon folder into `World of Warcraft\_forever_\Interface\AddOns\` with a directory junction, then `/reload` in game.

## License

- The addon is licensed under the **GNU LGPL v3.0 or later** (see [COPYING.LESSER](COPYING.LESSER) and [COPYING](COPYING)).
- Standalone libraries developed in this repository carry their own `LICENSE` file (MIT) in their folder.
