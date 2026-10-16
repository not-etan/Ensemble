#!/usr/bin/env python3
"""Convert branding/overview.md to the BBCode used on addon sites (CurseForge/Wago style).

Usage: python3 tools/md_to_bbcode.py branding/overview.md > dist/overview-bbcode.txt
"""
import re, sys

ACCENT = "#7EB7FF"

def inline(t):
    t = t.replace("\\|", "|")
    t = re.sub(r"`([^`]+)`", r"[font=Courier New]\1[/font]", t)
    t = re.sub(r"\*\*(.+?)\*\*", r"[b]\1[/b]", t)
    t = re.sub(r"(?<![\*\w])\*(?!\s)(.+?)(?<!\s)\*(?![\*\w])", r"[i]\1[/i]", t)
    return t

def convert(md):
    out, in_list = [], False
    def close():
        nonlocal in_list
        if in_list:
            out.append("[/list]"); in_list = False
    for line in md.split("\n"):
        m_item = re.match(r"^(?:- |\d+\. )(.*)$", line)
        if m_item:
            if not in_list:
                out.append("[list]"); in_list = True
            out.append("[*]" + inline(m_item.group(1)))
            continue
        close()
        if line.startswith("# "):
            out.append("[size=6][b]" + inline(line[2:]) + "[/b][/size]")
        elif line.startswith("## "):
            out.append("[size=5][b][color=" + ACCENT + "]" + inline(line[3:]) + "[/color][/b][/size]")
        elif line.startswith("### "):
            out.append("[size=4][b]" + inline(line[4:]) + "[/b][/size]")
        elif line.strip() == "---":
            out.append("")
        elif line.startswith("|"):
            cells = [c.strip() for c in re.split(r"(?<!\\)\|", line.strip())[1:-1]]
            if not cells or set("".join(cells)) <= set("-: ") or cells[0].lower() == "command":
                continue
            out.append("▸ " + inline(cells[0]) + " — " + inline(cells[1]))
        else:
            out.append(inline(line))
    close()
    return "\n".join(out)

if __name__ == "__main__":
    sys.stdout.write(convert(open(sys.argv[1], encoding="utf-8").read()).rstrip("\n"))
