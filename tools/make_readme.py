#!/usr/bin/env python3
"""Build the overview pages from branding/overview.md.

  python3 tools/make_readme.py branding/overview.md       > README.md                   (GitHub front page)
  python3 tools/make_readme.py --web branding/overview.md > dist/overview-curseforge.md (CurseForge description)

branding/overview.md is the source of truth for the overview. Both versions start the
same way: the header graphic, then a line of links to the full guide, changelog and license
(the overview's H1 is dropped: the header carries the name), and end with the license
note. README.md uses paths inside the repo, which only work on GitHub. The --web version
uses full web addresses (header from raw.githubusercontent.com, the guide on the wiki),
because CurseForge's description (Markdown) has no repo to resolve paths against.
Don't edit either output by hand; edit branding/overview.md and run tools/package.sh.
"""
import re, sys

REPO = "https://github.com/not-etan/Ensemble"
RAW = "https://raw.githubusercontent.com/not-etan/Ensemble/main/"
# The overview header (option A strip, October 25, 2026); the wiki's Home keeps the full banner (make_wiki.py).
BANNER = "branding/header-1600x200.png"

args = [a for a in sys.argv[1:] if a != "--web"]
web = "--web" in sys.argv[1:]
src = open(args[0], encoding="utf-8").read().splitlines()
# Drop the overview's H1: the header carries the name.
if src and src[0].startswith("# "):
    src = src[1:]

if web:
    guide, changelog, license_ = REPO + "/wiki", REPO + "/blob/main/CHANGELOG.md", REPO + "/blob/main/LICENSE"
    out = ["![Ensemble](%s%s)" % (RAW, BANNER)]
else:
    guide, changelog, license_ = "docs/Guide.md", "CHANGELOG.md", "LICENSE"
    out = [
        "<!-- Generated from branding/overview.md by tools/make_readme.py. Edit that file instead. -->",
        '<p align="center"><img src="%s" alt="Ensemble" width="100%%"></p>' % BANNER,
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

if web:
    # Every link and image must be a full web address: a repo path shows as broken on CurseForge.
    bad = [t for t in re.findall(r"\]\(([^)]+)\)|src=\"([^\"]+)\"", text) for t in t if t and not re.match(r"https?://", t)]
    if bad:
        sys.exit("make_readme.py --web: links that only work inside the repo: " + ", ".join(bad))
    # The page's layout starts with the header graphic and the links line (the author, October 25, 2026).
    lines = text.split("\n")
    if not (lines[0].startswith("![Ensemble](https://") and lines[2].startswith("📖 **[Full guide](https://")):
        sys.exit("make_readme.py --web: the description must start with the header graphic, then the links line")

sys.stdout.write(text)
