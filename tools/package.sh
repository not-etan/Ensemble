#!/bin/sh
# Build the release zip: dist/KeystoneCommand-<version>.zip (version from the TOC).
# Zip layout:
#   KeystoneCommand/             the addon folder players install (code and media only)
#   KeystoneCommand-README.md    a copy of README.md, beside the folder, for people who
#                                download the zip (named so it can't clash with other
#                                addons' readmes if the zip is extracted into AddOns)
set -e
cd "$(dirname "$0")/.."
rm -f KeystoneCommand/README.md KeystoneCommand/CODE_REVIEW.md
VER=$(sed -n 's/^## Version: *//p' KeystoneCommand/KeystoneCommand.toc | tr -d '\r')
mkdir -p dist
rm -rf dist/stage && mkdir -p dist/stage
cp -r KeystoneCommand dist/stage/
cp README.md dist/stage/KeystoneCommand-README.md
rm -f "dist/KeystoneCommand-$VER.zip"
(cd dist/stage && zip -qr "../KeystoneCommand-$VER.zip" KeystoneCommand KeystoneCommand-README.md -x '*.DS_Store')
rm -rf dist/stage
python3 tools/md_to_bbcode.py branding/overview.md > branding/overview-bbcode.txt
echo "dist/KeystoneCommand-$VER.zip"
