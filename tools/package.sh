#!/bin/sh
# Build the release zip: dist/KeystoneCommand-<version>.zip (version from the TOC).
# Zip layout:
#   KeystoneCommand/             the addon folder players install (code and media only)
#   KeystoneCommand-README.md    a copy of docs/Guide.md (the full guide), beside the folder, for people who
#                                download the zip (named so it can't clash with other
#                                addons' readmes if the zip is extracted into AddOns)
#   KeystoneCommand/LICENSE.txt  the license, so it travels with every install
set -e
cd "$(dirname "$0")/.."
rm -f KeystoneCommand/README.md
VER=$(sed -n 's/^## Version: *//p' KeystoneCommand/KeystoneCommand.toc | tr -d '\r')
mkdir -p dist
rm -rf dist/stage && mkdir -p dist/stage
cp -r KeystoneCommand dist/stage/
cp docs/Guide.md dist/stage/KeystoneCommand-README.md
cp LICENSE dist/stage/KeystoneCommand/LICENSE.txt
rm -f "dist/KeystoneCommand-$VER.zip"
(cd dist/stage && zip -qr "../KeystoneCommand-$VER.zip" KeystoneCommand KeystoneCommand-README.md -x '*.DS_Store')
rm -rf dist/stage
python3 tools/md_to_bbcode.py branding/overview.md > branding/overview-bbcode.txt
python3 tools/make_readme.py branding/overview.md > README.md
echo "dist/KeystoneCommand-$VER.zip"
