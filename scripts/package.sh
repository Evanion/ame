#!/usr/bin/env bash
# Build a release zip (no tests, docs, dev tooling): dist/AzerothMercantileExchange-<version>.zip
#   scripts/package.sh 0.1.0-beta.1
# Mirrors .pkgmeta for local/manual releases. The zip holds two addon folders (core + load-on-demand history) with
# their embedded libraries, ready to unzip into Interface/AddOns. Needs: bash, zip, luac5.1, lua5.1.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: scripts/package.sh <version>}"
STAGE=.release
CORE="$STAGE/AzerothMercantileExchange"
HIST="$STAGE/AzerothMercantileExchange_History"
rm -rf "$STAGE"
mkdir -p "$CORE" "$HIST" dist

# addon
cp AzerothMercantileExchange.toc embeds.xml COPYING COPYING.LESSER "$CORE/"
cp -r Core Locales LibAMEChart-1.0 media "$CORE/"
cp AzerothMercantileExchange_History/AzerothMercantileExchange_History.toc AzerothMercantileExchange_History/History.lua \
  "$HIST/"

# embedded libraries: only what embeds.xml loads (plus licences)
need() { [ -e "$1" ] || { echo "missing $1 - run scripts/fetch-libs.sh (LibDBIcon: see that script)" >&2; exit 1; }; }
mkdir -p "$CORE/Libs/Ace3" "$CORE/Libs/LibDeflate"
for m in LibStub CallbackHandler-1.0 AceGUI-3.0 AceConfig-3.0 AceComm-3.0 AceLocale-3.0; do
  need "Libs/Ace3/$m"
  cp -r "Libs/Ace3/$m" "$CORE/Libs/Ace3/"
done
cp Libs/Ace3/LICENSE.txt "$CORE/Libs/Ace3/"
for f in LibDeflate.lua lib.xml LICENSE.txt; do
  need "Libs/LibDeflate/$f"
  cp "Libs/LibDeflate/$f" "$CORE/Libs/LibDeflate/"
done
for d in LibDataBroker-1.1 LibDBIcon-1.0; do
  need "Libs/$d"
  cp -r "Libs/$d" "$CORE/Libs/"
done
find "$STAGE" \( -name .git -o -name .github -o -name tests -o -name '*.md' -o -name '*.textile' \) -prune \
  -exec rm -rf {} +

# version stamps
sed -i "s/@project-version@/$VERSION/" "$CORE/AzerothMercantileExchange.toc" "$HIST/AzerothMercantileExchange_History.toc"
sed -i "s/^ns.VERSION = .*/ns.VERSION = \"$VERSION\"/" "$CORE/Core/Init.lua"

# checks: every Lua file parses, every file a TOC or XML references exists
find "$STAGE" -name '*.lua' -print0 | xargs -0 -n1 luac5.1 -p
lua5.1 scripts/check-package.lua "$CORE/AzerothMercantileExchange.toc" "$HIST/AzerothMercantileExchange_History.toc"

ZIP="dist/AzerothMercantileExchange-$VERSION.zip"
rm -f "$ZIP"
(cd "$STAGE" && zip -qr "../$ZIP" AzerothMercantileExchange AzerothMercantileExchange_History)
echo "$ZIP ($(du -h "$ZIP" | cut -f1)), $(unzip -l "$ZIP" | tail -1 | awk '{print $2}') files"
