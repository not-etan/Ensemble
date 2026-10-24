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

Presentation added for the wiki only (the guide stays plain):
- A bullet that starts with a bold label ("- **Label:** text" or
  "- **Label** (detail): text") becomes a "### Label" heading with the text as a
  paragraph, so pages read as short labeled sections and GitHub lists them in
  the page's outline. Other bullets stay bullets.
- PAGES gives each page an icon and a one-line lead; the sidebar uses the icons.
- CALLOUTS adds GitHub note/tip/warning boxes after a named section. MOVE takes
  a sentence out of a section's text when its callout repeats it.
- Home gets the banner; every page gets previous/next links.
"""
import os
import re
import sys

REPO = "https://github.com/not-etan/Ensemble"
BANNER = "https://raw.githubusercontent.com/not-etan/Ensemble/main/branding/banner-1200x300.png"

TITLES = {
    "Groups you could join (Group Finder search results)": "Groups You Could Join",
    "Everything else": "Settings and More",
    "Checking the addon against your game client": "Checking Against Your Client",
}
HOME_SECTIONS = {"Install", "Use"}

# title -> (icon, one-line lead shown at the top of the page)
PAGES = {
    "Home": ("🏠", None),
    "Composition": ("🧩", "Who should we bring?"),
    "Applicants": ("📥", "Who's applying, and who should you invite?"),
    "Groups You Could Join": ("🔎", "How well would you fit the groups you're browsing?"),
    "Dungeon": ("🏰", "What do you need to know, in the order you meet it?"),
    "Plan": ("🗝️", "Who handles what?"),
    "Settings and More": ("⚙️", "Settings, affixes, history and slash commands."),
    "Boss Cards": ("🐉", "A short card for every boss, and the window that follows your key."),
    "Checking Against Your Client": ("🩺", "Make sure the addon and your game agree."),
    "Reporting a Problem": ("🐞", "Build a report to paste into an issue."),
    "License": ("⚖️", None),
}

# page title -> [(after section heading, kind, text)]; kind is NOTE, TIP, IMPORTANT or WARNING.
CALLOUTS = {
    "Home": [("Opening it", "TIP", "New here? The tour runs the first time you open the window. Replay it any time from Settings > General.")],
    "Applicants": [("Invite", "NOTE", "The addon never invites anyone on its own. Every invite takes your click.")],
    "Groups You Could Join": [("A line for your Sign Up note", "TIP", "Click the box, press Ctrl+C, then paste it into Blizzard's Sign Up note.")],
    "Plan": [("Changing an assignment", "NOTE", "Your changes last for this session only, and stop applying when that player changes spec or leaves.")],
    "Settings and More": [("Settings", "WARNING", "Resetting everything can't be undone.")],
    "Reporting a Problem": [(None, "NOTE", "Nothing is sent anywhere. You copy the report and paste it yourself.")],
}
# sentences removed from a section's text because its callout says them
MOVE = []


def title_for(heading):
    if heading in TITLES:
        return TITLES[heading]
    small = {"a", "an", "and", "or", "the", "of", "to", "for", "in", "on", "by"}
    words = heading.split()
    return " ".join(w if (i and w.lower() in small) else w[:1].upper() + w[1:]
                    for i, w in enumerate(words))


def slug(title):
    return re.sub(r"[^A-Za-z0-9-]", "", title.replace(" ", "-"))


def icon(title):
    return PAGES.get(title, ("📄", None))[0]


def link(title):
    return "[[%s %s|%s]]" % (icon(title), title, slug(title))


def fix_links(text):
    # Relative repo links (LICENSE, CHANGELOG.md, ...) don't resolve on the wiki.
    return re.sub(r"\]\((?!https?:|#|mailto:)([^)]+)\)",
                  lambda m: "](%s/blob/main/%s)" % (REPO, m.group(1).lstrip("./")), text)


LABEL = re.compile(r"^- \*\*(.+?)\*\*(.*)$")


def sectionize(lines):
    """Turn '- **Label:** text' bullets into '### Label' + paragraph."""
    out = []
    for line in lines:
        m = LABEL.match(line)
        if m:
            label, rest = m.group(1), m.group(2)
            body = None
            if label.endswith(":"):
                label, body = label[:-1], rest.strip()
            elif rest.startswith(":"):
                body = rest[1:].strip()
            else:
                p = re.match(r"^ \(([^)]*)\):\s*(.*)$", rest)
                if p:
                    t = p.group(2)
                    body = "*%s*\n\n%s" % (p.group(1), t[:1].upper() + t[1:])
            if body is not None:
                body = body[:1].upper() + body[1:]
                if out and out[-1].strip():
                    out.append("")
                out += ["### " + label, "", body, ""]
                continue
        out.append(line)
    return out


def callouts(title, lines):
    items = CALLOUTS.get(title, [])
    for after, kind, text in items:
        box = ["", "> [!%s]" % kind, "> " + text, ""]
        if after is None:
            lines = lines + box
            continue
        heads = [i for i, l in enumerate(lines) if l.startswith("### " + after)]
        if not heads:
            continue
        i = heads[0] + 1
        while i < len(lines) and not lines[i].startswith("#"):
            i += 1
        lines = lines[:i] + box + lines[i:]
    return lines


def split(lines):
    """Return (home_lines, [(title, body_lines), ...]) in guide order."""
    home, pages = [], []
    cur = None
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


def finish(title, body):
    text = "\n".join(body)
    for s in MOVE:
        text = text.replace(s, "")
    body = text.split("\n")
    # Page headings: the guide's "#### X" sit one level under a section.
    body = [("### " + l[5:]) if l.startswith("#### ") else l for l in body]
    body = sectionize(body)
    body = callouts(title, body)
    lead = PAGES.get(title, (None, None))[1]
    head = ["> %s **%s**" % (icon(title), lead), ""] if lead else []
    out = "\n".join(head + body)
    return re.sub(r"\n{3,}", "\n\n", out).strip() + "\n"


def main():
    src, out = sys.argv[1], sys.argv[2]
    lines = open(src, encoding="utf-8").read().splitlines()
    home, pages = split(lines)
    order = ["Home"] + [t for t, _ in pages]

    os.makedirs(out, exist_ok=True)
    for f in os.listdir(out):
        if f.endswith(".md"):
            os.remove(os.path.join(out, f))

    def nav(title):
        i = order.index(title)
        parts = []
        if i > 0:
            parts.append("← " + link(order[i - 1]))
        if i + 1 < len(order):
            parts.append(link(order[i + 1]) + " →")
        return ["", "---", "", " · ".join(parts)]

    def write(name, text):
        with open(os.path.join(out, name + ".md"), "w", encoding="utf-8") as fh:
            fh.write(fix_links(text))

    home_text = finish("Home", home)
    contents = ["", "## 📚 Pages", ""] + ["- " + link(t) for t, _ in pages]
    write("Home", "\n".join(['<p align="center"><img src="%s" alt="Ensemble" width="100%%"></p>' % BANNER, "",
                             home_text] + contents + nav("Home")) + "\n")
    for title, body in pages:
        write(slug(title), finish(title, body) + "\n".join(nav(title)) + "\n")

    side = [link("Home"), "", "**Tabs**", ""] + ["- " + link(t) for t, _ in pages]
    side += ["", "---", "", "[Repository](%s) · [Changelog](%s/blob/main/CHANGELOG.md)" % (REPO, REPO)]
    write("_Sidebar", "\n".join(side) + "\n")
    write("_Footer", "This wiki is generated from [`docs/Guide.md`](%s/blob/main/docs/Guide.md). "
                     "Edits made here are overwritten on the next update.\n" % REPO)
    print("\n".join(slug(t) for t in order))


if __name__ == "__main__":
    main()
