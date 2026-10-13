#!/usr/bin/env python3
"""Convert the Apple Localizable.strings (the source of truth) to Flutter .arb files.

Run: python3 -I flutter/tool/strings_to_arb.py   (from anywhere; paths are relative to this file)
Writes flutter/lib/l10n/app_<locale>.arb (English is the template) and key_map.json (Dart name -> Apple key).
Exit code 1 on: unparsable file, Dart-name collision, placeholder mismatch against English. Missing keys are copied
from English and listed in the report (exit 0).
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "Sources" / "IPTVMac" / "Resources"
OUT = ROOT / "flutter" / "lib" / "l10n"
DART_RESERVED = set("""abstract as assert async await break case catch class const continue covariant default deferred do dynamic else
enum export extends extension external factory false final finally for function get hide if implements import in interface is late library
mixin new null of on operator part required rethrow return set show static super switch sync this throw true try typedef var void when
while with yield localeName delegate supportedLocales localizationsDelegates hashCode runtimeType toString""".split())

# ---------- parser for the old-style plist text format ----------
ESC = {"n": "\n", "t": "\t", "r": "\r", "a": "\a", "b": "\b", "f": "\f", "v": "\v", '"': '"', "'": "'", "\\": "\\"}


def read_text(path):
    raw = path.read_bytes()
    if raw[:2] in (b"\xff\xfe", b"\xfe\xff"):
        return raw.decode("utf-16")
    return raw.decode("utf-8-sig")


def parse_strings(text, name="?"):
    """Returns an ordered dict key -> value. Raises ValueError with line number on any syntax problem."""
    i, n, out = 0, len(text), {}

    def err(msg):
        raise ValueError(f"{name}:{text.count(chr(10), 0, i) + 1}: {msg}")

    def skip():
        nonlocal i
        while i < n:
            if text[i].isspace():
                i += 1
            elif text.startswith("//", i):
                while i < n and text[i] != "\n":
                    i += 1
            elif text.startswith("/*", i):
                j = text.find("*/", i + 2)
                if j < 0:
                    err("unterminated comment")
                i = j + 2
            else:
                return

    def token():
        nonlocal i
        if i >= n:
            err("unexpected end of file")
        if text[i] != '"':  # unquoted token: letters, digits, _ . / - $ :
            m = re.compile(r"[A-Za-z0-9_./$:\-]+").match(text, i)
            if not m:
                err(f"unexpected character {text[i]!r}")
            i = m.end()
            return m.group()
        i += 1
        buf = []
        while True:
            if i >= n:
                err("unterminated string")
            c = text[i]
            if c == '"':
                i += 1
                return "".join(buf)
            if c != "\\":
                buf.append(c)
                i += 1
                continue
            i += 1
            if i >= n:
                err("unterminated escape")
            c = text[i]
            if c in ESC:
                buf.append(ESC[c])
                i += 1
            elif c in "uU":
                h = text[i + 1:i + 5]
                if not re.fullmatch(r"[0-9a-fA-F]{4}", h):
                    err("bad \\u escape")
                cp = int(h, 16)
                i += 5
                # UTF-16 surrogate pair written as two \u escapes
                if 0xD800 <= cp < 0xDC00 and text[i:i + 2] in ("\\u", "\\U") and re.fullmatch(r"[0-9a-fA-F]{4}", text[i + 2:i + 6]):
                    lo = int(text[i + 2:i + 6], 16)
                    if 0xDC00 <= lo < 0xE000:
                        cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00)
                        i += 6
                buf.append(chr(cp))
            elif c in "01234567":
                m = re.compile(r"[0-7]{1,3}").match(text, i)
                buf.append(chr(int(m.group(), 8)))
                i = m.end()
            else:
                err(f"unknown escape \\{c}")

    while True:
        skip()
        if i >= n:
            return out
        key = token()
        skip()
        if i >= n or text[i] != "=":
            err(f"expected '=' after key {key!r}")
        i += 1
        skip()
        val = token()
        skip()
        if i >= n or text[i] != ";":
            err(f"expected ';' after value of {key!r}")
        i += 1
        if key in out:
            err(f"duplicate key {key!r}")
        out[key] = val


# ---------- format specifiers -> ICU placeholders ----------
SPEC = re.compile(r"%(?:(\d+)\$)?[-+ #0]*\d*(?:\.\d+)?(hh|h|ll|l|q|z|t|j)?([@dDiuUxXoOfFeEgGsScC%])")
TYPES = {"@": "String", "s": "String", "S": "String", "c": "String", "C": "String", "f": "double", "F": "double", "e": "double",
         "E": "double", "g": "double", "G": "double"}  # everything else (d i u x o ...) is int


def convert(value, key, loc):
    """Returns (icu_message, {index: type}). Unnumbered specifiers count 1,2,3.. in order; numbered ones keep their number."""
    types, parts, pos, nxt, numbered, plain = {}, [], 0, 1, False, False
    for m in SPEC.finditer(value):
        parts.append(escape_icu(value[pos:m.start()]))
        pos = m.end()
        conv = m.group(3)
        if conv == "%":
            parts.append("%")
            continue
        if m.group(1):
            idx, numbered = int(m.group(1)), True
        else:
            idx, nxt, plain = nxt, nxt + 1, True
        if numbered and plain:
            raise ValueError(f"{loc} {key}: mixes numbered and unnumbered specifiers")
        t = TYPES.get(conv, "int")
        if types.setdefault(idx, t) != t:
            raise ValueError(f"{loc} {key}: placeholder {idx} used with two types")
        parts.append("{p%d}" % idx)
    rest = value[pos:]
    parts.append(escape_icu(rest))
    msg = "".join(parts)
    # a '%' that the regex did not understand (e.g. "100% sure") would be a bug in the source: fail loudly
    for m in re.finditer(r"%", value):
        if not SPEC.match(value, m.start()) and not (m.start() > 0 and value[m.start() - 1] == "%" and SPEC.match(value, m.start() - 1)):
            raise ValueError(f"{loc} {key}: stray '%' in {value!r}")
    return msg, types


def escape_icu(s):
    """gen-l10n ICU: a quote is an escape char, braces start placeholders."""
    return s.replace("'", "''").replace("{", "'{'").replace("}", "'}'")


def dart_name(key):
    segs = [s for s in re.split(r"[^A-Za-z0-9]+", key) if s]
    if not segs:
        raise ValueError(f"key {key!r} has no usable characters")
    name = segs[0][0].lower() + segs[0][1:] + "".join(s[0].upper() + s[1:] for s in segs[1:])
    if not re.fullmatch(r"[a-z][A-Za-z0-9]*", name) or name in DART_RESERVED:
        raise ValueError(f"key {key!r} -> {name!r} is not a usable Dart identifier")
    return name


def locale_of(folder):
    return folder.removesuffix(".lproj").replace("-", "_")


def main():
    errors, report = [], []
    files = sorted(SRC.glob("*.lproj/Localizable.strings"))
    if not (SRC / "en.lproj" / "Localizable.strings").exists():
        sys.exit("en.lproj/Localizable.strings not found")
    data = {}
    for f in files:
        loc = locale_of(f.parent.name)
        try:
            data[loc] = parse_strings(read_text(f), f"{f.parent.name}/Localizable.strings")
        except ValueError as e:
            errors.append(str(e))
    if errors:
        sys.exit("\n".join(errors))

    en = data["en"]
    names, key_map = {}, {}
    for k in en:
        nm = dart_name(k)
        if nm in names:
            errors.append(f"Dart name collision: {k!r} and {names[nm]!r} -> {nm}")
        names[nm] = k
        key_map[nm] = k
    en_conv = {}
    for k, v in en.items():
        try:
            en_conv[k] = convert(v, k, "en")
        except ValueError as e:
            errors.append(str(e))
    if errors:
        sys.exit("\n".join(errors))

    outputs = {}  # file name -> text; nothing is written if any error is found
    for loc in sorted(data, key=lambda l: (l != "en", l)):
        strings, arb, missing = data[loc], {"@@locale": loc}, []
        for k in strings.keys() - en.keys():
            report.append(f"{loc}: extra key not in English (ignored): {k}")
        for nm, k in names.items():
            en_msg, en_types = en_conv[k]
            if k in strings:
                try:
                    msg, types = convert(strings[k], k, loc)
                except ValueError as e:
                    errors.append(str(e))
                    continue
                if types != en_types:
                    errors.append(f"{loc} {k}: placeholders {sorted(types.items())} differ from English {sorted(en_types.items())}")
                    continue
            else:
                msg, missing = en_msg, missing + [k]
            arb[nm] = msg
            if loc == "en" and en_types:
                arb["@" + nm] = {"placeholders": {"p%d" % i: {"type": t} for i, t in sorted(en_types.items())}}
        if missing:
            report.append(f"{loc}: {len(missing)} missing key(s), English copied: {', '.join(missing)}")
        outputs[f"app_{loc}.arb"] = arb
    # gen-l10n needs a base locale (zh) for zh_Hans / zh_Hant: use a copy of the first variant (zh_Hans = Simplified, the usual default)
    for loc in sorted(data):
        base = loc.split("_")[0]
        if base not in data and f"app_{base}.arb" not in outputs:
            outputs[f"app_{base}.arb"] = {**outputs[f"app_{loc}.arb"], "@@locale": base}
            report.append(f"{base}: no Apple folder, generated fallback as a copy of {loc} (gen-l10n requires a base locale)")
    outputs["key_map.json"] = key_map
    if not errors:
        OUT.mkdir(parents=True, exist_ok=True)
        for stale in OUT.glob("app_*.arb"):
            stale.unlink()
        for fname, obj in outputs.items():
            (OUT / fname).write_text(json.dumps(obj, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    print(f"{len(en)} keys, {len(data)} locales")
    print("\n".join(report) if report else "report: no missing keys, no extra keys")
    if errors:
        print("\nERRORS:\n" + "\n".join(errors), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
