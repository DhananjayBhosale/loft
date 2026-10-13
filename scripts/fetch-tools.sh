#!/bin/bash
# Copies the Mole cleaner from a Homebrew install into Vendor/tools/mole so the app can bundle it.
# fclones ships in Vendor/tools already.
set -euo pipefail
cd "$(dirname "$0")/.."
brew list mole >/dev/null 2>&1 || brew install mole
src="$(brew --prefix mole)"
rm -rf Vendor/tools/mole && mkdir -p Vendor/tools/mole
cp -R "$src/bin" "$src/libexec" "$src/LICENSE" Vendor/tools/mole/
echo "Mole copied to Vendor/tools/mole"
