# Azeroth Mercantile Exchange (AME)

A World of Warcraft: Forever addon that records auction house prices over time and turns them into a futures-market view: price and volume charts, trend and volatility signals, and a screener for items worth investing in.

- It reuses Auctionator's full scans, so you never have to scan twice.
- Prices are kept separately per realm and auction house (Alliance, Horde or Neutral).
- Planned: sharing scans with guildmates and trusted friends.

**Status:** pre-alpha. See [docs/design.md](docs/design.md).

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
