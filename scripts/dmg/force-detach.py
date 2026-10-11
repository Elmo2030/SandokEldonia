"""Runs dmgbuild with a forced `hdiutil detach`.

On some Macs (seen with Xcode 27 installed) a plain detach is refused system-wide with "Simulators are still shutting down", which makes
dmgbuild fail after the layout is written. A forced detach works. make-dmg.sh only uses this after a normal dmgbuild run failed.
Usage: build/venv/bin/python scripts/dmg/force-detach.py <the same arguments as dmgbuild>
"""
import plistlib, subprocess, sys
import dmgbuild.core as core

# a failed earlier run leaves its temporary writable image mounted: unmount it first
info = plistlib.loads(subprocess.run(["/usr/bin/hdiutil", "info", "-plist"], capture_output=True).stdout)
for img in info.get("images", []):
    if "/.temp" in img.get("image-path", "") and img["image-path"].endswith("IPTVMac.dmg"):
        for ent in img.get("system-entities", []):
            if ent.get("dev-entry", "").count("s") == 0:
                subprocess.run(["/usr/bin/hdiutil", "detach", "-force", ent["dev-entry"]], capture_output=True)

orig = core.hdiutil
def hdiutil(cmd, *args, **kw):
    if cmd == "detach" and "-force" not in args:
        args = ("-force",) + args
    return orig(cmd, *args, **kw)
core.hdiutil = hdiutil

from dmgbuild.__main__ import main
sys.argv = ["dmgbuild"] + sys.argv[1:]
main()
