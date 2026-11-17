#!/usr/bin/env bash
# Upload a release to CurseForge (upload API). Credentials come from .env in the repo root (never committed):
#   CURSEFORGE_CI_API_TOKEN=...   CURSEFORGE_PROJECT_ID=...
#
#   scripts/release.sh --check                       verify the token, list game versions that look like Forever
#   scripts/release.sh <version> [beta|alpha|release] [changelog.md]
#
# Builds dist/AzerothMercantileExchange-<version>.zip with scripts/package.sh, then uploads it as the given release
# type (default beta) with the changelog (default: docs/changelog/<version>.md). Game version IDs: set
# CURSEFORGE_GAME_VERSIONS (comma-separated IDs) in .env, or the script picks every version named like the TOC
# interface (Forever 1.16.x). Needs: curl, python3.
set -euo pipefail
cd "$(dirname "$0")/.."

[ -f .env ] || { echo "no .env with CURSEFORGE_CI_API_TOKEN / CURSEFORGE_PROJECT_ID" >&2; exit 1; }
# read KEY=value lines (tolerates quotes, 'export ', CRLF); nothing is printed
while IFS= read -r line || [ -n "$line" ]; do
  line="${line%$'\r'}"
  line="${line#export }"
  case "$line" in '' | '#'*) continue ;; esac
  key="${line%%=*}"
  value="${line#*=}"
  value="${value%\"}"; value="${value#\"}"; value="${value%\'}"; value="${value#\'}"
  case "$key" in CURSEFORGE_CI_API_TOKEN | CURSEFORGE_PROJECT_ID | CURSEFORGE_GAME_VERSIONS) export "$key=$value" ;; esac
done < .env
: "${CURSEFORGE_CI_API_TOKEN:?missing in .env}"
: "${CURSEFORGE_PROJECT_ID:?missing in .env}"

API=https://wow.curseforge.com/api
auth=(-H "X-Api-Token: $CURSEFORGE_CI_API_TOKEN")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fetch_versions() {
  local code
  code=$(curl -s -o "$TMP/types.json" -w '%{http_code}' "${auth[@]}" "$API/game/version-types")
  [ "$code" = 200 ] || { echo "CurseForge said $code for the token (check CURSEFORGE_CI_API_TOKEN)" >&2; exit 1; }
  curl -s -o "$TMP/versions.json" "${auth[@]}" "$API/game/versions"
}

# game versions matching the TOC's first interface number, e.g. 16001 -> 1.16.1
pick_versions() {
  python3 - "$TMP/types.json" "$TMP/versions.json" "$1" <<'PY'
import json, sys
types = {t["id"]: t["name"] for t in json.load(open(sys.argv[1]))}
versions = json.load(open(sys.argv[2]))
iface = sys.argv[3]
major, minor, patch = int(iface[:-4] or 0), int(iface[-4:-2]), int(iface[-2:])
want = f"{major}.{minor}.{patch}"
hits = [v for v in versions if v["name"] == want]
mode = sys.argv[4] if len(sys.argv) > 4 else "ids"
for v in hits:
    print(v["id"] if mode == "ids" else f'{v["id"]}  {v["name"]}  ({types.get(v["gameVersionTypeID"], "?")})')
PY
}

IFACE=$(sed -n 's/^## Interface: *\([0-9]*\).*/\1/p' AzerothMercantileExchange.toc)

if [ "${1:-}" = "--check" ]; then
  fetch_versions
  echo "token OK, project $CURSEFORGE_PROJECT_ID"
  echo "game versions named like interface $IFACE:"
  python3 - "$TMP/types.json" "$TMP/versions.json" "$IFACE" list <<'PY'
import json, sys
types = {t["id"]: t["name"] for t in json.load(open(sys.argv[1]))}
versions = json.load(open(sys.argv[2]))
iface = sys.argv[3]
want = f"{int(iface[:-4] or 0)}.{int(iface[-4:-2])}.{int(iface[-2:])}"
for v in versions:
    if v["name"] == want or "orever" in types.get(v["gameVersionTypeID"], ""):
        print(f'  {v["id"]}  {v["name"]}  ({types.get(v["gameVersionTypeID"], "?")})')
PY
  exit 0
fi

VERSION="${1:?usage: scripts/release.sh <version> [beta|alpha|release] [changelog.md]  |  --check}"
TYPE="${2:-beta}"
CHANGELOG="${3:-docs/changelog/$VERSION.md}"
[ -f "$CHANGELOG" ] || { echo "changelog $CHANGELOG not found" >&2; exit 1; }

bash scripts/package.sh "$VERSION"
ZIP="dist/AzerothMercantileExchange-$VERSION.zip"

fetch_versions
if [ -n "${CURSEFORGE_GAME_VERSIONS:-}" ]; then
  IDS="$CURSEFORGE_GAME_VERSIONS"
else
  IDS=$(pick_versions "$IFACE" | paste -sd, -)
fi
[ -n "$IDS" ] || { echo "no CurseForge game version matches interface $IFACE; set CURSEFORGE_GAME_VERSIONS" >&2; exit 1; }

python3 - "$VERSION" "$TYPE" "$CHANGELOG" "$IDS" > "$TMP/metadata.json" <<'PY'
import json, sys
version, rtype, changelog, ids = sys.argv[1:5]
print(json.dumps({
    "changelog": open(changelog, encoding="utf-8").read(),
    "changelogType": "markdown",
    "displayName": f"Azeroth Mercantile Exchange {version}",
    "gameVersions": [int(i) for i in ids.split(",") if i],
    "releaseType": rtype,
}))
PY

code=$(curl -s -o "$TMP/upload.json" -w '%{http_code}' "${auth[@]}" \
  -F "metadata=<$TMP/metadata.json" \
  -F "file=@$ZIP" \
  "$API/projects/$CURSEFORGE_PROJECT_ID/upload-file")
if [ "$code" = 200 ]; then
  echo "uploaded $ZIP as $TYPE (CurseForge file id $(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["id"])' "$TMP/upload.json"))"
else
  echo "upload failed ($code): $(cat "$TMP/upload.json")" >&2
  exit 1
fi
