#!/usr/bin/env python3
"""Build the overview pages from branding/overview.md.

  python3 tools/make_readme.py branding/overview.md > README.md   (GitHub front page)

branding/overview.md is the source of truth for the overview (it also feeds the
BBCode for CurseForge). It adds the banner at the top, links to the full guide,
changelog and license, and the license note at the end. README.md uses paths inside
the repo, which only work on GitHub. Don't edit it by hand; edit branding/overview.md
and run tools/package.sh.
"""
import sys

src = open(sys.argv[1], encoding="utf-8").read().splitlines()
# Drop the overview's H1: the banner carries the name.
if src and src[0].startswith("# "):
    src = src[1:]

guide, changelog, license_ = "docs/Guide.md", "CHANGELOG.md", "LICENSE"
out = [
    "<!-- Generated from branding/overview.md by tools/make_readme.py. Edit that file instead. -->",
    '<p align="center"><img src="branding/banner-1200x300.png" alt="Ensemble" width="100%"></p>',
]
out += [
    "",
    "📖 **[Full guide](%s)** · 📝 **[Changelog](%s)** · ⚖️ **[License](%s)**" % (guide, changelog, license_),
]
out += src
out += [
    "",
    "---",
    "",
    "## ⚖️ License",
    "",
    "All rights reserved. You may use Ensemble in game, but its code, data, artwork, name and logo may not be copied, modified or redistributed without permission. See [`LICENSE`](%s)." % license_,
    "",
]
text = "\n".join(out)

sys.stdout.write(text)
