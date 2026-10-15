#!/usr/bin/env python3
"""Build the repo's front page (README.md) from branding/overview.md.

branding/overview.md is the source of truth for the overview (it also feeds the
BBCode for addon sites). README.md adds the GitHub-only parts: the banner at the
top, links to the full guide and changelog, and the license. Don't edit
README.md by hand; edit branding/overview.md and run tools/package.sh.
"""
import sys

src = open(sys.argv[1], encoding="utf-8").read().splitlines()
# Drop the overview's H1: the banner carries the name.
if src and src[0].startswith("# "):
    src = src[1:]
out = [
    "<!-- Generated from branding/overview.md by tools/make_readme.py. Edit that file instead. -->",
    '<p align="center"><img src="branding/banner-1200x300.png" alt="Keystone Command" width="100%"></p>',
    "",
    "📖 **[Full guide](docs/Guide.md)** · 📝 **[Changelog](CHANGELOG.md)** · ⚖️ **[License](LICENSE)**",
]
out += src
out += [
    "",
    "---",
    "",
    "## ⚖️ License",
    "",
    "All rights reserved. You may use Keystone Command in game, but its code, data, artwork, name and logo may not be copied, modified or redistributed without permission. See [`LICENSE`](LICENSE).",
    "",
]
sys.stdout.write("\n".join(out))
