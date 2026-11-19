"""Put the uids back into a scene written by a headless save.

    python -I Tools/fix_city_uids.py [Scenes/City.tscn ...]

A headless `ResourceSaver.save()` drops every `uid://` from the file it writes,
because nothing loads the uid cache outside the editor (Docs/TECH_NOTES.md §9).
The scene still loads -- every `ext_resource` keeps its path -- but the project
otherwise carries uids everywhere, and a path-only reference silently stops
following a file that is later moved.

So this reads each `ext_resource` path, finds that file's real uid, and writes
it back into the `[ext_resource ...]` line. Where a uid cannot be found the
line is left alone and said so, rather than guessed at.

Where a uid lives, by kind of file:
    foo.gd    -> foo.gd.uid, which holds the uid and nothing else
    foo.png   -> foo.png.import, as `uid="uid://..."`
    foo.tscn  -> inside the file, in its `[gd_scene ...]` header
    foo.tres  -> inside the file, in its `[gd_resource ...]` header
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EXT = re.compile(r'^\[ext_resource ([^\]]*)\]$', re.M)
PATH_IN = re.compile(r'path="res://([^"]+)"')
HEADER_UID = re.compile(r'^\[gd_(?:scene|resource)[^\]]*uid="(uid://[^"]+)"', re.M)
IMPORT_UID = re.compile(r'^uid="(uid://[^"]+)"', re.M)


def uid_for(res_path: str) -> str | None:
    """The uid of one `res://` file, or None when it has none to give."""
    target = ROOT / res_path
    if res_path.endswith(".gd"):
        side = target.with_suffix(".gd.uid")
        return side.read_text(encoding="utf-8").strip() if side.exists() else None
    if res_path.endswith((".tscn", ".tres")):
        if not target.exists():
            return None
        found = HEADER_UID.search(target.read_text(encoding="utf-8"))
        return found.group(1) if found else None
    side = Path(str(target) + ".import")
    if side.exists():
        found = IMPORT_UID.search(side.read_text(encoding="utf-8"))
        return found.group(1) if found else None
    return None


def fix(scene: Path) -> int:
    text = scene.read_text(encoding="utf-8")
    added = 0
    missing = []

    def patch(match: re.Match) -> str:
        nonlocal added
        body = match.group(1)
        if "uid=" in body:
            return match.group(0)
        where = PATH_IN.search(body)
        if where is None:
            return match.group(0)
        uid = uid_for(where.group(1))
        if uid is None:
            missing.append(where.group(1))
            return match.group(0)
        # Godot writes the uid straight after the type, so match that order.
        body = body.replace('path="', 'uid="%s" path="' % uid, 1)
        added += 1
        return "[ext_resource %s]" % body

    text = EXT.sub(patch, text)
    scene.write_text(text, encoding="utf-8", newline="\n")
    print("%s: %d uid(s) restored" % (scene.relative_to(ROOT), added))
    for path in missing:
        print("  no uid found for %s (left by path)" % path)
    return added


if __name__ == "__main__":
    targets = sys.argv[1:] or ["Scenes/City.tscn"]
    for name in targets:
        fix(ROOT / name)
