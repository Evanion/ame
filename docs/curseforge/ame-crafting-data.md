# AME Crafting Data

**Profession and recipe data for [Azeroth Mercantile Exchange](https://www.curseforge.com/wow/addons/ame) (AME) in WoW Forever.**

This is the data behind AME's **Crafting** tab. With it installed, AME can rank the recipes your characters know by how much gold they make at today's auction house prices, tell you whether to sell your materials or craft them first, find recipes on the auction house worth buying, and plan the cheapest way to level a profession.

It adds nothing to your screen by itself, and it loads only when you open the Crafting tab - no cost at login or while you play.

## What's inside

- **Every crafting recipe** of every profession: what it makes, how many per craft, and its reagents
- **Every recipe item** (patterns, plans, formulas, schematics): which recipe it teaches, its profession, and the skill needed to learn it
- **Skill-up colors** for every recipe: where it turns yellow, green and grey
- **Recipe cooldowns** (transmutes, Mooncloth...)
- **Vendor prices** of the trade supplies vendors sell (vials, thread, flux, dyes, spices...)

It's made for WoW Forever, including the recipes Forever added or changed - Classic-era data gets those wrong. Item and recipe names come from your game client, so it works in every language.

## Always current

The data is rebuilt automatically for each new WoW Forever version and released within a day of a game update.

## Requirements

- [Azeroth Mercantile Exchange](https://www.curseforge.com/wow/addons/ame) - switch the Crafting tab on under Settings › General
- WoW Forever

## For addon authors

Loaded on demand by name (`AzerothMercantileExchange_Crafting`), it sets one global table, `AME_CraftingData`, keyed by item and recipe IDs. The format is documented at the top of `Recipes.lua`.

## About the data

The data comes from Blizzard, via [wago.tools](https://wago.tools) - thank you - and is only repackaged here. We claim no ownership of it; the MIT licence covers the packaging, not the data.
