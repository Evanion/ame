# AME Crafting Data

**Recipe data for Azeroth Mercantile Exchange's Crafting tab: what every profession can make in WoW Forever, what it costs, and how it levels.**

AME Crafting Data is a companion to [Azeroth Mercantile Exchange](https://www.curseforge.com/wow/addons/ame) (AME), the auction house addon that records prices from your own scans. With this data installed, AME's **Crafting** tab can tell you which of your recipes make money at today's auction house prices, whether to sell your materials or craft them into something first, which recipes for sale on the auction house are worth buying, and the cheapest way to level a profession.

On its own it adds nothing to your screen: it's the reference data AME reads. It loads only when you open the Crafting tab, so it costs nothing at login or while you play.

## What it lets AME do

### Top earners
Every recipe your characters know, ranked by **gold per day**: profit per craft times how many the market actually buys a day. A 50g profit that sells once a week ranks below a 2g profit that sells 200 a day. Reagents are priced the cheapest way you could get them - bought, from a vendor (vials, thread, flux... their vendor prices are in this data), crafted from cheaper materials, or from your own bags at what selling them would earn. Recipes with a cooldown (transmutes, Mooncloth) count one craft per cooldown.

*Example: Elixir of the Mongoose - reagents 7g 84s, sells for 12g 82s after the AH cut, 28 sell a day: about 136g a day for whoever brews them.*

### Sell or refine
For the materials in your bags and bank: sell them as they are, or craft them into something worth more? *120 Thorium Ore nets 126g sold raw, or 157g smelted into bars and sold - and the bar market takes about 90 a day, so list them over two days.*

### Recipes to buy
Recipe items on the auction house (patterns, plans, formulas, schematics) that one of your characters could learn and doesn't know yet, ranked by **payback**: the recipe's price divided by what it would earn a day. This data is what tells AME which recipe an auction house item teaches, which profession it's for and the skill it needs - the game itself can't look that up.

### Leveling guides
The cheapest path from your current skill to the one you want, recalculated from live prices. For every skill point AME picks the recipe with the lowest cost per point, using each recipe's **skill-up colors** (orange, yellow, green, grey - from this data) and the skill-up chance. Choose a goal - cheapest, best recovery (what the results sell back for), fewest crafts, or use your own materials first - and the guide lists each step: what to craft, how many, what it costs, what the results get back, and when to buy or train a recipe. One click puts every reagent on a shopping list.

## What's inside

All of it is Blizzard's own data for the current WoW Forever version (via [wago.tools](https://wago.tools)), so it matches the game - including the recipes Forever added or changed, which Classic-era data gets wrong:

- **Every crafting recipe** of every profession: what it makes, how many per craft, and its reagents (about 2,500 recipes)
- **Every recipe item**: the recipe it teaches, its profession and the skill needed to learn it (about 2,000)
- **Skill-up colors** for every recipe: where it turns yellow, green and grey
- **Recipe cooldowns** (transmutes, Mooncloth...)
- **Vendor prices** of the trade supplies vendors sell (vials, thread, flux, dyes, spices...)

IDs only: item and recipe names come from your game client, so it works in every language.

## Always current

The data is rebuilt automatically from each new WoW Forever build and released as a new version within a day of a game update, with the number of recipes per profession in the changelog. Keep it updated alongside AME.

## Requirements

- [Azeroth Mercantile Exchange](https://www.curseforge.com/wow/addons/ame) (switch the Crafting tab on under Settings › General)
- WoW Forever

## For addon authors

The data sets one global table, `AME_CraftingData` (recipes, recipe items, skill colors, cooldowns, vendor prices, keyed by ID), loaded on demand by name (`AzerothMercantileExchange_Crafting`). The format is documented at the top of `Recipes.lua`.

## About the data

The recipe data comes from Blizzard, via [wago.tools](https://wago.tools) - thank you - and is only repackaged here. We claim no ownership of it; the MIT licence covers the packaging, not the data.
