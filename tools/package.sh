#!/bin/sh
# Build the release zip: dist/Ensemble-<version>.zip (version from the TOC).
# A local test build: the same layout as the release zip that .github/workflows/release.yml
# uploads (BigWigs packager, .pkgmeta): one Ensemble/ folder with the code, media and
# LICENSE.txt (a copy of LICENSE, kept identical; the tests check).
# Also writes the store descriptions: dist/overview-bbcode.txt (CurseForge) and
# dist/overview-wago.md (Wago: Markdown with full web addresses), and regenerates README.md.
set -e
cd "$(dirname "$0")/.."
rm -f Ensemble/README.md
VER=$(sed -n 's/^## Version: *//p' Ensemble/Ensemble.toc | tr -d '\r')
mkdir -p dist
rm -rf dist/stage && mkdir -p dist/stage
cp -r Ensemble dist/stage/
cmp -s LICENSE Ensemble/LICENSE.txt || { echo 'Ensemble/LICENSE.txt differs from LICENSE: copy it over' >&2; exit 1; }
rm -f "dist/Ensemble-$VER.zip"
(cd dist/stage && zip -qr "../Ensemble-$VER.zip" Ensemble -x '*.DS_Store')
rm -rf dist/stage
python3 tools/md_to_bbcode.py branding/overview.md > dist/overview-bbcode.txt
python3 tools/make_readme.py branding/overview.md > README.md
python3 tools/make_readme.py --wago branding/overview.md > dist/overview-wago.md
echo "dist/Ensemble-$VER.zip"
echo "dist/overview-bbcode.txt"
echo "dist/overview-wago.md"
