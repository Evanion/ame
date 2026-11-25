#!/usr/bin/env bash
# Fetch embedded libraries into Libs/ for local development (the packager does the same from .pkgmeta).
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p Libs
fetch() {
  local dir="$1" url="$2"
  if [ -d "Libs/$dir/.git" ]; then
    git -C "Libs/$dir" pull -q --ff-only
  else
    git clone -q --depth 1 "$url" "Libs/$dir"
  fi
  echo "Libs/$dir: $(git -C "Libs/$dir" rev-parse --short HEAD)"
}
fetch Ace3 https://github.com/WoWUIDev/Ace3.git
fetch LibDeflate https://github.com/SafeteeWoW/LibDeflate.git
fetch LibDataBroker-1.1 https://github.com/tekkub/libdatabroker-1-1.git
# LibDBIcon-1.0 is SVN-only (WowAce); the packager fetches it for releases. For development, use svn if available,
# otherwise copy Libs/LibDBIcon-1.0 from any installed addon that embeds it (BugSack, DBM, ...).
if [ ! -f Libs/LibDBIcon-1.0/LibDBIcon-1.0.lua ] && command -v svn >/dev/null; then
  svn export -q https://repos.wowace.com/wow/libdbicon-1-0/trunk/LibDBIcon-1.0 Libs/LibDBIcon-1.0
fi
# LibSharedMedia-3.0 is SVN-only too: svn if available, otherwise copy it from an installed addon (BugSack, DBM, ...).
if [ ! -f Libs/LibSharedMedia-3.0/LibSharedMedia-3.0.lua ] && command -v svn >/dev/null; then
  svn export -q https://repos.wowace.com/wow/libsharedmedia-3-0/trunk/LibSharedMedia-3.0 Libs/LibSharedMedia-3.0
fi
# say what's still missing (CI installs svn; a release can't be built without them)
for lib in LibDBIcon-1.0 LibSharedMedia-3.0; do
  [ -f "Libs/$lib/$lib.lua" ] && echo "Libs/$lib: ok" || echo "Libs/$lib: missing (needs svn, or a copy from an installed addon)" >&2
done
