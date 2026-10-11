#!/usr/bin/env python3
"""Generates ios/Resources/Acknowledgements.txt (the plain text the app shows in Settings > About) from Acknowledgements.md.
Usage: python3 scripts/ios-acknowledgements.py [--check]     --check: write nothing, exit 1 when the .txt is out of date.
Rules: '#' / '##' headings get an underline ('=' / '-'), '###' a blank line before, code fences are dropped (their content is copied untouched),
inline `code` loses its backticks. Standard library only; the output is deterministic."""
import pathlib, re, sys

RES = pathlib.Path(__file__).resolve().parent.parent / "ios/Resources"

def convert(md: str) -> str:
    out, fenced = [], False
    for line in md.split("\n"):
        if line.startswith("```"):
            fenced = not fenced
            continue
        if fenced:
            out.append(line)
            continue
        m = re.match(r"(#{1,3}) (.*)", line)
        if m:
            level, title = len(m.group(1)), m.group(2).replace("`", "")
            if level == 1: out += [title, "=" * len(title)]
            elif level == 2: out += [title, "-" * len(title)]
            else: out += [title]
            continue
        out.append(line.replace("`", ""))
    return re.sub(r"\n{3,}", "\n\n", "\n".join(out)).strip("\n") + "\n"

if __name__ == "__main__":
    want = convert((RES / "Acknowledgements.md").read_text(encoding="utf-8"))
    dst = RES / "Acknowledgements.txt"
    if "--check" in sys.argv:
        if not dst.exists() or dst.read_text(encoding="utf-8") != want:
            sys.exit("ios/Resources/Acknowledgements.txt is out of date: run python3 scripts/ios-acknowledgements.py")
        print("Acknowledgements.txt is up to date")
    else:
        dst.write_text(want, encoding="utf-8")
        print(f"wrote {dst.relative_to(RES.parent.parent)} ({len(want)} bytes)")
