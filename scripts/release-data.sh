#!/usr/bin/env bash
# Release the crafting data library (AzerothMercantileExchange_Crafting) on its own CurseForge project (its TOC's
# X-Curse-Project-ID): the next patch version (data-v1.0.N -> 1.0.N+1), tagged on the checked-out commit (main, where
# the data arrived by pull request) and uploaded. Run by .github/workflows/crafting-data-release.yml; never releases
# AME itself.
#
#   CURSEFORGE_CI_API_TOKEN   from the environment (a GitHub secret)
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
  echo "The data comes from Blizzard, via wago.tools, and is only repackaged here; we claim no ownership of it."
  echo "The MIT licence covers the packaging, not the data."
  echo
  [ -n "${SUMMARY:-}" ] && [ -f "$SUMMARY" ] && cat "$SUMMARY"
} >"$CHANGELOG"

if [ "${DRY_RUN:-}" = 1 ]; then
  echo "dry run: not tagging or uploading"
  cat "$CHANGELOG"
  exit 0
fi

# tag the release on the commit the data is on (main's: it arrives by pull request)
git diff --quiet -- "$DIR" || { echo "uncommitted changes in $DIR: data reaches main by pull request" >&2; exit 1; }
git tag "data-v$VERSION"
git push -q origin "data-v$VERSION"

# upload
: "${CURSEFORGE_CI_API_TOKEN:?missing}"
CURSEFORGE_DATA_PROJECT_ID=$(sed -n 's/^## X-Curse-Project-ID: *\([0-9]*\).*/\1/p' "$TOC" | tr -d '\r')
: "${CURSEFORGE_DATA_PROJECT_ID:?missing: X-Curse-Project-ID in $TOC}"
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
