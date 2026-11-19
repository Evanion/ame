#!/usr/bin/env python3
"""Generate AME's crafting data (recipes and recipe items) from the game's own client tables.

Reads WoW Forever's DB2 tables as CSV from wago.tools and writes
AzerothMercantileExchange_Crafting/Recipes.lua - a load-on-demand addon, so the data only loads when Crafting
needs it. IDs only: names come from the client in the player's language.

    python3 scripts/gen-recipes.py                 # the latest wowf build
    python3 scripts/gen-recipes.py --build 1.60.1.70959
    python3 scripts/gen-recipes.py --check         # exit 1 when the output would change (CI)

What comes from where (see docs/plans/m16-crafting.md):
  SkillLineAbility  recipe spell -> profession (SkillLine), yellow / grey skill (TrivialSkillLineRankLow / High)
  SpellEffect       recipe spell -> product (Effect 24 "create item": EffectItemType, yield EffectBasePointsF)
  SpellReagents     recipe spell -> reagents and counts
  Item, ItemXItemEffect, ItemEffect
                    recipe item (class 9) -> the spell it teaches (the item effect triggered "on learn", 6)
  ItemSparse        recipe item -> profession and skill needed to learn it (RequiredSkill / RequiredSkillRank)
"""
import argparse
import csv
import re
import io
import json
import os
import sys
import time
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "AzerothMercantileExchange_Crafting", "Recipes.lua")
CACHE = os.path.join(ROOT, ".cache", "wago")
PRODUCT = "wowf"
# an honest User-Agent that names the tool (wago.tools answers it)
USER_AGENT = "AME-recipe-generator/1.0 (+https://github.com/Evanion/ame)"

# crafting and gathering professions; everything else in the skill tables (racials, riding, poisons, test lines,
# Comprehension) is left out
PROFESSIONS = {129, 164, 165, 171, 182, 185, 186, 197, 202, 333, 356, 393}
EFFECT_CREATE_ITEM = 24
EFFECT_ENCHANT_ITEM = 53
TRIGGER_ON_LEARN = 6
CLASS_RECIPE = 9
MAX_SHRINK = 0.10  # a profession losing more than this share of its recipes stops the update (a broken table?)
TABLES = ["SkillLineAbility", "SpellEffect", "SpellReagents", "Item", "ItemXItemEffect", "ItemEffect", "ItemSparse"]


def fetch(url):
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=120) as r:
        return r.read()


def latest_build():
    builds = json.loads(fetch("https://wago.tools/api/builds"))
    entries = builds.get(PRODUCT) or []
    if not entries:
        sys.exit("no %s build listed on wago.tools" % PRODUCT)
    return entries[0]["version"]


def table(build, name):
    """A table's rows (dicts by column name: layouts differ between game versions), cached per build."""
    path = os.path.join(CACHE, build, name + ".csv")
    if not os.path.exists(path):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        data = fetch("https://wago.tools/db2/%s/csv?build=%s&useHotfixes" % (name, build))
        with open(path, "wb") as f:
            f.write(data)
        time.sleep(1)  # be gentle
    with open(path, newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def num(v):
    try:
        return int(float(v or 0))
    except ValueError:
        return 0


def build_data(build):
    t = {name: table(build, name) for name in TABLES}
    effects = {}
    for e in t["SpellEffect"]:
        effects.setdefault(num(e["SpellID"]), []).append(e)
    reagents = {num(r["SpellID"]): r for r in t["SpellReagents"]}

    recipes = {}
    for a in t["SkillLineAbility"]:
        line, spell = num(a["SkillLine"]), num(a["Spell"])
        if line not in PROFESSIONS or spell in recipes:
            continue
        out, made, kind = 0, 0, None
        for e in sorted(effects.get(spell, []), key=lambda e: num(e["EffectIndex"])):
            if num(e["Effect"]) == EFFECT_CREATE_ITEM and num(e["EffectItemType"]) > 0:
                out, made, kind = num(e["EffectItemType"]), max(1, num(e["EffectBasePointsF"])), "item"
                break
            if num(e["Effect"]) == EFFECT_ENCHANT_ITEM:
                kind = "enchant"
        if not kind:
            continue  # abilities that make nothing (e.g. the profession's own spell, gathering skills)
        r = reagents.get(spell)
        pairs = []
        if r:
            for i in range(8):
                item, count = num(r.get("Reagent_%d" % i)), num(r.get("ReagentCount_%d" % i))
                if item > 0 and count > 0:
                    pairs += [item, count]
        recipes[spell] = {
            "line": line,
            "out": out,
            "made": made,
            "yellow": num(a["TrivialSkillLineRankLow"]),
            "grey": num(a["TrivialSkillLineRankHigh"]),
            "reagents": pairs,
        }

    item_effect = {num(e["ID"]): e for e in t["ItemEffect"]}
    by_item = {}
    for x in t["ItemXItemEffect"]:
        e = item_effect.get(num(x["ItemEffectID"]))
        if e and num(e["TriggerType"]) == TRIGGER_ON_LEARN:
            by_item.setdefault(num(x["ItemID"]), []).append(num(e["SpellID"]))
    sparse = {num(s["ID"]): s for s in t["ItemSparse"]}
    items = {}
    for i in t["Item"]:
        item = num(i["ID"])
        if num(i["ClassID"]) != CLASS_RECIPE:
            continue
        taught = sorted(s for s in by_item.get(item, []) if s in recipes)
        if not taught:
            continue  # class books, or recipes for something we don't track
        s = sparse.get(item, {})
        items[item] = {
            "line": num(s.get("RequiredSkill")) or recipes[taught[0]]["line"],
            "rank": num(s.get("RequiredSkillRank")),
            "spells": taught,
        }
    return recipes, items


def lua(build, recipes, items):
    lines = [
        "-- Generated by scripts/gen-recipes.py from WoW Forever's client tables (wago.tools, build %s)." % build,
        "-- Do not edit: fixes go in CraftingData.OVERRIDES (Core/CraftingData.lua). IDs only; names come from the client.",
        "-- The game data is Blizzard Entertainment's, only repackaged here (see LICENSE).",
        "--",
        "-- recipes[spellID] = { profession, product item (0 = enchant), made per craft, yellow, grey,",
        "--                      reagent, count, reagent, count, ... }",
        "-- items[recipeItemID] = { profession, skill to learn, taught spell, taught spell... }",
        "AME_CraftingData = {",
        '  build = "%s",' % build,
        "  recipes = {",
    ]
    for spell in sorted(recipes):
        r = recipes[spell]
        values = [r["line"], r["out"], r["made"], r["yellow"], r["grey"]] + r["reagents"]
        lines.append("    [%d] = { %s }," % (spell, ", ".join(str(v) for v in values)))
    lines += ["  },", "  items = {"]
    for item in sorted(items):
        i = items[item]
        values = [i["line"], i["rank"]] + i["spells"]
        lines.append("    [%d] = { %s }," % (item, ", ".join(str(v) for v in values)))
    lines += ["  },", "}", ""]
    return "\n".join(lines)


def counts(text):
    """recipes per profession in a generated file"""
    out = {}
    recipes = text.split("  items = {")[0]
    for line in re.findall(r"^    \[\d+\] = \{ (\d+),", recipes, re.M):
        out[int(line)] = out.get(int(line), 0) + 1
    return out


def shrunk(old, new):
    """professions that lost more than MAX_SHRINK of their recipes: { profession: (before, after) }"""
    return {p: (n, new.get(p, 0)) for p, n in old.items() if new.get(p, 0) < n * (1 - MAX_SHRINK)}


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--build", help="wago.tools build (default: the latest %s)" % PRODUCT)
    ap.add_argument("--check", action="store_true", help="exit 1 if the output would change")
    ap.add_argument("--allow-shrink", action="store_true", help="accept professions losing many recipes")
    ap.add_argument("--latest", action="store_true", help="print the latest build and exit")
    ap.add_argument("--summary", help="append a Markdown summary of the change to this file (CI)")
    args = ap.parse_args()
    if args.latest:
        print(latest_build())
        return
    build = args.build or latest_build()
    recipes, items = build_data(build)
    text = lua(build, recipes, items)
    per_line = {}
    for r in recipes.values():
        per_line[r["line"]] = per_line.get(r["line"], 0) + 1
    print("build %s: %d recipes, %d recipe items; per profession %s" % (
        build, len(recipes), len(items), json.dumps(dict(sorted(per_line.items())))))
    old = open(OUT, encoding="utf-8").read() if os.path.exists(OUT) else None
    before, after = counts(old or ""), counts(text)
    lost = shrunk(before, after)
    if args.summary and old != text:
        old_build = re.search(r'build = "([^"]+)"', old or "")
        with open(args.summary, "a", encoding="utf-8") as f:
            f.write("Crafting data from WoW Forever build %s (was %s).\n\n" % (
                build, old_build.group(1) if old_build else "none"))
            f.write("| Profession | Recipes before | after |\n|---|---|---|\n")
            for p in sorted(set(before) | set(after)):
                f.write("| %d | %d | %d |\n" % (p, before.get(p, 0), after.get(p, 0)))
    if lost and not args.allow_shrink:
        sys.exit("professions lost more than %d%% of their recipes: %s - check the tables, or --allow-shrink" % (
            MAX_SHRINK * 100, lost))
    if args.check:
        sys.exit(0 if old == text else 1)
    if old != text:
        os.makedirs(os.path.dirname(OUT), exist_ok=True)
        with io.open(OUT, "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
        print("wrote", os.path.relpath(OUT, ROOT))
    else:
        print("unchanged")


if __name__ == "__main__":
    main()
