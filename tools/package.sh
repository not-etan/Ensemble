#!/bin/sh
# Build the release zip: dist/KeystoneCommand-<version>.zip (version from the TOC).
# A local test build: the same layout as the release zip that .github/workflows/release.yml
# uploads (BigWigs packager, .pkgmeta): one KeystoneCommand/ folder with the code, media and
# LICENSE.txt (a copy of LICENSE, kept identical; the tests check).
set -e
cd "$(dirname "$0")/.."
rm -f KeystoneCommand/README.md
VER=$(sed -n 's/^## Version: *//p' KeystoneCommand/KeystoneCommand.toc | tr -d '\r')
mkdir -p dist
rm -rf dist/stage && mkdir -p dist/stage
cp -r KeystoneCommand dist/stage/
cmp -s LICENSE KeystoneCommand/LICENSE.txt || { echo 'KeystoneCommand/LICENSE.txt differs from LICENSE: copy it over' >&2; exit 1; }
rm -f "dist/KeystoneCommand-$VER.zip"
(cd dist/stage && zip -qr "../KeystoneCommand-$VER.zip" KeystoneCommand -x '*.DS_Store')
rm -rf dist/stage
python3 tools/md_to_bbcode.py branding/overview.md > dist/overview-bbcode.txt
python3 tools/make_readme.py branding/overview.md > README.md
echo "dist/KeystoneCommand-$VER.zip"
echo "dist/overview-bbcode.txt"
