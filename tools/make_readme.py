#!/usr/bin/env python3
"""Build the overview pages from branding/overview.md.

  python3 tools/make_readme.py branding/overview.md          > README.md            (GitHub front page)
  python3 tools/make_readme.py --wago branding/overview.md   > dist/overview-wago.md (Wago description)

branding/overview.md is the source of truth for the overview (it also feeds the
BBCode for CurseForge). Both versions add the banner at the top, links to the full
guide, changelog and license, and the license note at the end. README.md uses
paths inside the repo, which only work on GitHub. The Wago version uses full web
addresses (banner from raw.githubusercontent.com, the guide on the wiki), because
Wago's description has no repo to resolve paths against. Don't edit either output
by hand; edit branding/overview.md and run tools/package.sh.
"""
import re, sys

REPO = "https://github.com/not-etan/Ensemble"
RAW = "https://raw.githubusercontent.com/not-etan/Ensemble/main/"

args = [a for a in sys.argv[1:] if a != "--wago"]
wago = "--wago" in sys.argv[1:]
src = open(args[0], encoding="utf-8").read().splitlines()
# Drop the overview's H1: the banner carries the name.
if src and src[0].startswith("# "):
    src = src[1:]

if wago:
    banner = "![Ensemble](%sbranding/banner-1200x300.png)" % RAW
    guide, changelog, license_ = REPO + "/wiki", REPO + "/blob/main/CHANGELOG.md", REPO + "/blob/main/LICENSE"
    out = [banner]
else:
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

if wago:
    # Every link and image must be a full web address: a repo path shows as broken on Wago.
    bad = [t for t in re.findall(r"\]\(([^)]+)\)|src=\"([^\"]+)\"", text) for t in t if t and not re.match(r"https?://", t)]
    if bad:
        sys.exit("make_readme.py --wago: links that only work inside the repo: " + ", ".join(bad))

sys.stdout.write(text)
