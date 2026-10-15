#!/usr/bin/env python3
"""Split docs/Guide.md into GitHub wiki pages with a sidebar.

Usage: python3 tools/make_wiki.py docs/Guide.md <wiki-dir>

The wiki is generated: every *.md file in <wiki-dir> is replaced on each run, so
edits made on the Wiki tab are overwritten. Edit docs/Guide.md instead.
GitHub runs this from .github/workflows/wiki.yml on every push to main that
touches the guide or this script.

How the guide maps to pages:
- Everything before the first "## " heading, plus "## Install" and the intro of
  "## Use" (before its first "### "), becomes Home.
- Each "### " heading under "## Use" becomes its own page (one per tab).
- Every other "## " heading becomes its own page.
Page titles come from the heading, with a few shortened in TITLES.
"""
import os
import re
import sys

TITLES = {
    "Groups you could join (Group Finder search results)": "Groups You Could Join",
    "Everything else": "Settings and More",
    "Checking the addon against your game client": "Checking Against Your Client",
    "Keeping the data current (by hand)": "Keeping the Data Current",
}
HOME_SECTIONS = {"Install", "Use"}
REPO = "https://github.com/not-etan/Keystone-Command"


def title_for(heading):
    if heading in TITLES:
        return TITLES[heading]
    # Title Case for page names, keeping short words lower.
    small = {"a", "an", "and", "or", "the", "of", "to", "for", "in", "on", "by"}
    words = heading.split()
    return " ".join(w if (i and w.lower() in small) else w[:1].upper() + w[1:]
                    for i, w in enumerate(words))


def slug(title):
    return re.sub(r"[^A-Za-z0-9-]", "", title.replace(" ", "-"))


def fix_links(text):
    # Relative repo links (LICENSE, CHANGELOG.md, ...) don't resolve on the wiki.
    return re.sub(r"\]\((?!https?:|#|mailto:)([^)]+)\)",
                  lambda m: "](%s/blob/main/%s)" % (REPO, m.group(1).lstrip("./")), text)


def split(lines):
    """Return (home_lines, [(title, body_lines), ...]) in guide order."""
    home, pages = [], []
    cur = None            # body list being filled
    in_use = False
    for line in lines[1:]:                      # skip the guide's H1
        h2 = re.match(r"^## (.+)$", line)
        h3 = re.match(r"^### (.+)$", line)
        if h2:
            name = h2.group(1).strip()
            in_use = name == "Use"
            if name in HOME_SECTIONS:
                cur = home
                home.append(line)
            else:
                cur = []
                pages.append((title_for(name), cur))
            continue
        if h3 and in_use:
            cur = []
            pages.append((title_for(h3.group(1).strip()), cur))
            continue
        (home if cur is None else cur).append(line)
    return home, pages


def main():
    src, out = sys.argv[1], sys.argv[2]
    lines = open(src, encoding="utf-8").read().splitlines()
    home, pages = split(lines)

    os.makedirs(out, exist_ok=True)
    for f in os.listdir(out):
        if f.endswith(".md"):
            os.remove(os.path.join(out, f))

    def write(name, body):
        text = "\n".join(body).strip() + "\n"
        with open(os.path.join(out, name + ".md"), "w", encoding="utf-8") as fh:
            fh.write(fix_links(text))

    contents = ["", "## Pages", ""] + ["- [[%s|%s]]" % (t, slug(t)) for t, _ in pages]
    write("Home", home + contents)
    for title, body in pages:
        write(slug(title), body)

    tabs = [t for t, _ in pages][:6]
    more = [t for t, _ in pages][6:]
    side = ["**[[Home]]**", "", "**The tabs**", ""]
    side += ["- [[%s|%s]]" % (t, slug(t)) for t in tabs]
    side += ["", "**More**", ""] + ["- [[%s|%s]]" % (t, slug(t)) for t in more]
    side += ["", "---", "", "[Repository](%s) · [Changelog](%s/blob/main/CHANGELOG.md)" % (REPO, REPO)]
    write("_Sidebar", side)
    write("_Footer", ["This wiki is generated from [`docs/Guide.md`](%s/blob/main/docs/Guide.md). "
                      "Edits made here are overwritten on the next update." % REPO])
    print("\n".join(["Home"] + [slug(t) for t, _ in pages]))


if __name__ == "__main__":
    main()
