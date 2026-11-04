#!/usr/bin/env python3
"""Release notes for one version, from CHANGELOG.md (used by .github/workflows/release.yml).

  python3 tools/release_notes.py v1.2.2          # print the "## 1.2.2" section
  python3 tools/release_notes.py --check v1.2.2  # fail unless the TOC version and CHANGELOG match the tag

The tag is the version with an optional "v" prefix and an optional suffix after a dash
("v1.2.2-beta" -> 1.2.2), so beta and alpha tags use the same section. HTML comments (the
highlights' "<!-- show: ... -->" targets) are left out of the notes. --check also refuses an
Ensemble/Highlights.lua that doesn't match CHANGELOG.md (tools/make_highlights.py).
"""
import os, re, sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))


def version_of(tag):
    m = re.match(r"^v?(\d+\.\d+\.\d+)(?:-.+)?$", tag.strip())
    if not m:
        sys.exit("tag %r doesn't look like a version (v1.2.3, v1.2.3-beta)" % tag)
    return m.group(1)


def section(version):
    text = open(os.path.join(ROOT, "CHANGELOG.md"), encoding="utf-8").read()
    m = re.search(r"^## %s[ \t]*\n(.*?)(?=^## |\Z)" % re.escape(version), text, re.M | re.S)
    if not m:
        return None
    return re.sub(r"[ \t]*<!--.*?-->", "", m.group(1), flags=re.S).strip()


def toc_version():
    toc = open(os.path.join(ROOT, "Ensemble", "Ensemble.toc"), encoding="utf-8").read()
    m = re.search(r"^## Version:\s*(\S+)", toc, re.M)
    return m.group(1) if m else None


def main(argv):
    check = "--check" in argv
    args = [a for a in argv if a != "--check"]
    if len(args) != 1:
        sys.exit(__doc__)
    ver = version_of(args[0])
    body = section(ver)
    if check:
        problems = []
        if toc_version() != ver:
            problems.append("the TOC says %s, the tag says %s" % (toc_version(), ver))
        if not body:
            problems.append("CHANGELOG.md has no '## %s' section" % ver)
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        import make_highlights
        if make_highlights.current() != make_highlights.build():
            problems.append("Ensemble/Highlights.lua doesn't match CHANGELOG.md (run tools/make_highlights.py)")
        if problems:
            sys.exit("Not releasing: " + "; ".join(problems) + ".")
        print("Tag, TOC and CHANGELOG agree on %s." % ver)
        return
    if not body:
        sys.exit("CHANGELOG.md has no '## %s' section" % ver)
    print("## Ensemble %s\n\n%s" % (ver, body))


if __name__ == "__main__":
    main(sys.argv[1:])
