#!/usr/bin/env bash
# Release the crafting data library (AzerothMercantileExchange_Crafting) on its own CurseForge project: the next
# patch version (data-v1.0.N -> 1.0.N+1), committed, tagged and uploaded. Run by .github/workflows/crafting-data.yml
# after scripts/gen-recipes.py changed AzerothMercantileExchange_Crafting/Recipes.lua; never releases AME itself.
#
#   CURSEFORGE_CI_API_TOKEN, CURSEFORGE_DATA_PROJECT_ID   from the environment (GitHub secrets)
#   SUMMARY=path   Markdown appended to the changelog (gen-recipes.py --summary)
#   DRY_RUN=1      package only: no commit, tag, push or upload
# Needs: git, zip, luac5.1, curl, python3.
set -euo pipefail
cd "$(dirname "$0")/.."

DIR=AzerothMercantileExchange_Crafting
TOC="$DIR/$DIR.toc"
BUILD=$(sed -n 's/^  build = "\(.*\)",$/\1/p' "$DIR/Recipes.lua")

# next patch version from the last data tag (first release: 1.0.0)
LAST=$(git tag --list 'data-v*' --sort=-v:refname | head -1)
if [ -z "$LAST" ]; then
  VERSION=1.0.0
else
  IFS=. read -r MAJOR MINOR PATCH <<<"${LAST#data-v}"
  VERSION="$MAJOR.$MINOR.$((PATCH + 1))"
fi
echo "crafting data $VERSION (WoW Forever build $BUILD)"

# package: the one folder, version stamped
STAGE=.release-data
rm -rf "$STAGE"
mkdir -p "$STAGE/$DIR" dist
cp "$TOC" "$DIR/Recipes.lua" "$DIR/LICENSE" "$STAGE/$DIR/" # MIT, unlike AME (LGPL)
sed -i "s/@project-version@/$VERSION/" "$STAGE/$TOC"
luac5.1 -p "$STAGE/$DIR/Recipes.lua"
ZIP="dist/$DIR-$VERSION.zip"
rm -f "$ZIP"
(cd "$STAGE" && zip -qr "../$ZIP" "$DIR")
echo "packaged $ZIP"

CHANGELOG=$(mktemp)
trap 'rm -f "$CHANGELOG"' EXIT
{
  echo "Recipe data for Azeroth Mercantile Exchange's Crafting tab, from WoW Forever build $BUILD via wago.tools."
  echo
  echo "The data comes from wago.tools and is World of Warcraft game data (Blizzard's), only repackaged here; we"
  echo "claim no ownership of it. The MIT licence covers the packaging, not the game data."
  echo
  [ -n "${SUMMARY:-}" ] && [ -f "$SUMMARY" ] && cat "$SUMMARY"
} >"$CHANGELOG"

if [ "${DRY_RUN:-}" = 1 ]; then
  echo "dry run: not committing, tagging or uploading"
  cat "$CHANGELOG"
  exit 0
fi

# commit the data (when it changed) and tag the release
git config user.name "${GIT_AUTHOR_NAME:-github-actions[bot]}"
git config user.email "${GIT_AUTHOR_EMAIL:-41898282+github-actions[bot]@users.noreply.github.com}"
if ! git diff --quiet -- "$DIR"; then
  git add "$DIR"
  git commit -q -m "Crafting data $VERSION: WoW Forever build $BUILD"
fi
git tag "data-v$VERSION"
git push -q origin HEAD "data-v$VERSION"

# upload
: "${CURSEFORGE_CI_API_TOKEN:?missing}"
: "${CURSEFORGE_DATA_PROJECT_ID:?missing}"
API=https://wow.curseforge.com/api
auth=(-H "X-Api-Token: $CURSEFORGE_CI_API_TOKEN")
TMP=$(mktemp -d)
curl -sf -o "$TMP/versions.json" "${auth[@]}" "$API/game/versions"
IFACE=$(sed -n 's/^## Interface: *\([0-9]*\).*/\1/p' "$TOC")
IDS=$(python3 - "$TMP/versions.json" "$IFACE" <<'PY'
import json, sys
iface = sys.argv[2]
want = f"{int(iface[:-4] or 0)}.{int(iface[-4:-2])}.{int(iface[-2:])}"
print(",".join(str(v["id"]) for v in json.load(open(sys.argv[1])) if v["name"] == want))
PY
)
[ -n "$IDS" ] || { echo "no CurseForge game version matches interface $IFACE" >&2; exit 1; }
python3 - "$VERSION" "$CHANGELOG" "$IDS" >"$TMP/metadata.json" <<'PY'
import json, sys
version, changelog, ids = sys.argv[1:4]
print(json.dumps({
    "changelog": open(changelog, encoding="utf-8").read(),
    "changelogType": "markdown",
    "displayName": f"AME Crafting Data {version}",
    "gameVersions": [int(i) for i in ids.split(",") if i],
    "releaseType": "release",
}))
PY
code=$(curl -s -o "$TMP/upload.json" -w '%{http_code}' "${auth[@]}" \
  -F "metadata=<$TMP/metadata.json" -F "file=@$ZIP" \
  "$API/projects/$CURSEFORGE_DATA_PROJECT_ID/upload-file")
[ "$code" = 200 ] || { echo "upload failed ($code): $(cat "$TMP/upload.json")" >&2; exit 1; }
echo "uploaded $ZIP"
