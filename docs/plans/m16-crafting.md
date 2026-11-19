# M16: Crafting — top earners, sell-or-refine, recipes worth buying

Status: phases 1-2 built (Core/Professions.lua; the generated data library and its release pipeline); plan otherwise
(Nov 2026). Research: "Recipe database for WoW Forever" (reports/, kept out of the repo) and the
in-game probe (`/amedev recipes`, Core/Dev/RecipeProbe.lua) on Forever 1.60.1.

## What it does

A Crafting tab (off by default, like the Market overview) that answers three questions across all your characters:

1. **What earns the most?** Every recipe your characters know, ranked by gold per day: profit per craft x what the
   market absorbs (the product's sell rate).
2. **Sell it raw or refine it?** For materials you hold: sell them, or craft and sell the result - whichever nets more.
3. **Which recipes are worth buying?** Recipe items on the auction house (from your scans) that one of your
   characters could learn, ranked by payback: recipe price / gold per day.

## What the game gives us (probe, Forever 1.60.1)

- Forever has retail's profession API (`C_TradeSkillUI`); the classic `GetTradeSkillInfo` family is gone.
- With a profession window open, `GetAllRecipeIDs` returns the profession's **whole catalog, unlearned recipes
  included** (Alchemy: 196 recipes, 30 learned), regardless of the window's filters. `GetRecipeInfo` says which are
  learned; `GetRecipeSchematic` gives output item, yield (min / max) and reagents for learned and unlearned alike.
- 196 matches the Alchemy count in Forever's own client data (wago.tools, product `wowf`): the two sources agree.
- With the window closed every call returns nothing: a profession is learned when a character opens it.
- Forever adds its own recipes (Alchemy Laboratory, Fermenter, Mana Well...) - a Classic Era table would be wrong.

So a character's professions give us everything about recipes in those professions. What the game can't tell us is
**which recipe a recipe item teaches** (no API maps item -> recipe) and the skill it needs. Only that ships.

## Architecture: learned at runtime, plus one small shipped table

### Learned in game (Core/Professions.lua)

- On `TRADE_SKILL_SHOW` / `TRADE_SKILL_LIST_UPDATE` (debounced, after `IsTradeSkillReady()`): read
  `GetBaseProfessionInfo` (profession, skill, max) and walk `GetAllRecipeIDs`. Skip linked / guild / NPC windows
  (`IsTradeSkillLinked`, `IsNPCCrafting`...), and don't save an empty or unnamed profession.
- Saved per account: `AME_DB.crafting.catalog[skillLine][recipeID] = { out, min, max, reagents = {{id, n}...},
  type }` (shared: the same for every character) and per character `known[charKey][skillLine] = { skill, max, at,
  learned = { [recipeID] = true } }`. Cooldowns via `GetRecipeCooldown` when the window is open.
- Spellbook (`GetProfessions` / `GetProfessionInfo`) says which professions a character has even before its window
  was opened, so the tab can say "open Alchemy once on Kke to include it".
- Size: Forever has ~3,350 item-creating recipes in all; a character sees only its professions' catalogs.

### Shipped (Data/RecipeItems_Forever.lua, generated)

`[recipeItemID] = { recipeID, skillLine, minSkill }` for every recipe item (patterns, plans, formulas, schematics,
recipes). From wago.tools DB2 for the `wowf` build: ItemXItemEffect + ItemEffect (item -> "learn" spell) ->
SpellEffect (learn -> taught recipe spell) -> SkillLineAbility (profession, MinSkillLineRank). Item and spell IDs
only: names come from the client in every language. Some hundreds of rows, a few KB.

Items teaching several recipes keep a list. Enchanting formulas teach enchants (no product item): kept, but valued
only once enchanting output is handled (later).

### Generator and updates (scripts/gen-recipe-items.py, CraftSim's model)

- Downloads the tables as CSV from `https://wago.tools/db2/<Table>/csv?build=<build>&useHotfixes`, with a browser-like
  User-Agent (plain requests got 403); columns picked by header name (Forever's tables use a 5.5.4-style layout);
  output sorted, so diffs are small.
- A `LAST_BUILD_wowf` file; a scheduled GitHub Action (every 6 h) checks `https://wago.tools/api/builds` and, when
  the build changed and the output differs, opens a PR. Merge by hand; release as usual (scripts/release.sh).
- Checks in CI: the table loads, row count within +-10% of the last one (else the PR says why), overrides valid.
- `Data/RecipeItems_overrides.lua`: hand fixes layered on top, never edited into the generated file.
- In game: when a scan shows a recipe the table maps differently (or a recipe item it lacks), log it with the build
  to `AME_DB.crafting.mismatches` so wrong rows get reported.

Retail later: the same generator with retail's tables (CraftSim's mapping); not part of the first version.

## As built: the data library (phase 2)

- `AzerothMercantileExchange_Crafting` is its own load-on-demand addon and its own CurseForge project ("AME Crafting
  Data"), loaded by Core/CraftingData.lua only when Crafting needs it. AME's releases declare it a required
  dependency (slug ame-crafting-data, project 1816764), so the CurseForge app installs it with AME; AME's own zip doesn't carry
  it. It holds every profession's recipes (product, yield, yellow / grey, reagents) and every recipe item (profession,
  skill to learn, taught recipes): 2,492 recipes and 2,013 recipe items for build 1.60.1.70959, 263 KB.
- scripts/gen-recipes.py builds it from the client tables on wago.tools (an honest User-Agent; cached under .cache/).
- .github/workflows/crafting-data.yml, daily and hands-off: latest wowf build -> already handled (Actions cache, keyed
  by build and generator)? stop -> regenerate -> unchanged? stop -> shrink guard + crafting data specs -> the next patch
  version (data-v1.0.N) committed, tagged and uploaded by scripts/release-data.sh; any failure opens an issue.
  One-time setup: the repository secret CURSEFORGE_CI_API_TOKEN (the token AME's releases already use).
- Hand fixes: CraftingData.OVERRIDES in Core/CraftingData.lua (shipped with AME, applied over the generated rows).

## The numbers (Core/Crafting.lua, pure)

All prices from the faction market index; AH cut and deposit from Settings; sell rates from the index.

- **Value of an input**, depending on where it comes from:
  - you'd buy it: market price (no cut);
  - you hold it: what selling it would net (market x (1 - cut) - deposit share) - its opportunity cost;
  - vendor reagents (vials, thread): vendor price;
  - craftable: the cheapest of the above and crafting it (recursive, chains like ore -> bar -> belt; cycles cut off).
- **Profit per craft** = product's net sale x yield - inputs.
- **Gold per day** = profit per craft x min(how many you can make, product's sell rate). Products that are bind on
  pickup (`bindType`) or never listed are excluded (can't be sold); a product with no history says so.
- **Sell or refine** for each stack you hold (per character, from Portfolio's holdings): net of selling the raw
  stack vs net of crafting and selling the product, limited by what the market absorbs.
- **Recipe payback** = recipe's buy price / gold per day of what it teaches, for characters with that profession,
  enough skill and the recipe unlearned. Recipes priced far below their usual price are flagged (the index knows).

## Leveling guides (phase 6)

Cheapest-to-best paths for leveling a profession, recalculated from live prices. For each skill level, every usable
recipe has an expected cost per skill point: crafts per point (1 / skill-up chance) x net cost per craft (reagents
minus what the result gets back: AH sale limited by sell rate, vendor, a later step's reagent, or disenchanting). A
dynamic-programming pass over skill levels picks the path; large purchases are priced against recorded order books
(Depth). Goals: cheapest, best recovery, fewest crafts, your materials first. One click puts the reagents on a
shopping list; progress follows the recorded skill.

Data (research: "Disenchant and skill color libraries", reports/; no reusable LGPL-compatible library exists, so AME
generates its own):

- Skill colors: Forever's SkillLineAbility (yellow = TrivialSkillLineRankLow, grey = TrivialSkillLineRankHigh,
  green = floor of their midpoint); the learn level (orange) from the recipe item's ItemSparse.RequiredSkillRank
  (SkillLineAbility's MinSkillLineRank is a placeholder). Forever moved 600+ thresholds versus Classic Era, so only
  Forever's own data is right. In game, `GetRecipeInfo().relativeDifficulty` (the live color) overrides the table,
  which also catches server hotfixes. Test / placeholder skill lines filtered out.
- Skill-up chance: the community formula (grey - skill) / (grey - yellow) between yellow and grey; 100% orange.
- Disenchanting: bands (item level x quality x weapon / armor) from Forever's ItemDisenchantLoot; the materials and
  chances per band written by hand from the documented classic rules (not copied from GPL databases), cross-checked
  against published measurements; items that can't be disenchanted from ItemSparse flags. AME also logs the player's
  own disenchants to catch Forever differences. Optional at runtime: DisenchantBuddy's API and SkillUp Forever's API
  when installed (pcall, version checks) - never their data copied in (both GPL-3.0).
- So the phase 2 generator ships full recipe data (products, reagents, yields, thresholds, learn level, how it's
  learned) for every profession, not only the recipe-item link: guides need professions nobody has opened yet.

## Where recipes come from (sources)

- Version 1: recipe items on the auction house (from scans) and trainer recipes. The generated table also records
  SkillLineAbility's AcquireMethod, so a recipe can say "train it at 250" or "needs the recipe item".
- Later: vendor sources (who sells which recipe, for how much, reputation / Merchant's Favor), learned from merchant
  windows (MERCHANT_SHOW) and seeded from AllTheThings' Forever data (MIT) if it checks out. Drop and quest sources
  are left out unless asked for.

## UI

- Settings > General: "Crafting" card, off by default (no work, no saved catalogs while off).
- Crafting tab (shared shell): modes Top earners | Sell or refine | Recipes to buy (toolbar button group); a
  character filter; the table (DataTable); a right sidebar with the selected recipe's breakdown (inputs and where each
  comes from, product, cut, deposit, sell rate, cooldown, which characters can craft). Right-click: add reagents to a
  shopping list (exists), open chart, search the AH.
- Status line: which characters / professions are recorded, and how old each catalog is.
- Later: profit per recipe in the profession window itself.
- Mockups first (design canvas), as for the Overview.

## Phases

1. Core/Professions.lua: record catalogs and known recipes (events, guards, SavedVariables), with specs over a fake
   `C_TradeSkillUI`. Dev probe stays for checks.
2. Generator + `Data/RecipeItems_Forever.lua` + overrides + CI check; scheduled Action.
3. Core/Crafting.lua: input values, chains, profit, gold per day, sell-or-refine, payback - pure, with specs and a
   real-data check against the market fixture.
4. Crafting tab, settings flag, Guide article, translations.
5. In-game check, mismatch log review, release.
6. Leveling guides (see above): a fourth Crafting mode.

## Still to check in game

- Recipe items: `C_Item.GetItemSpell` on a recipe item and its tooltip lines (put one in your bags and run
  `/amedev recipes`) - only to confirm the shipped mapping, not needed for it.
- Enchanting's recipe type (enchants vs items) and cooldown recipes (transmutes).
- Whether recipes with reputation or Merchant's Favor costs are marked (they can't be bought on the AH anyway).
- That `GetAllRecipeIDs` behaves the same for every profession (only Alchemy probed so far).
