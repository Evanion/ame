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
