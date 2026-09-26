#!/usr/bin/env python3
"""Curate a pinned chords-db guitar.json into Ponteio's offline seed data.

Usage: python3 scripts/import_chords_db.py /path/to/guitar.json
The source must be lib/guitar.json from commit df06fa7b425cf5fd29485ff6591236b3557e3fac.
"""

import json
import sys
from pathlib import Path


ROOTS = {
    "C": 0, "Csharp": 1, "D": 2, "Eb": 3, "E": 4, "F": 5,
    "Fsharp": 6, "G": 7, "Ab": 8, "A": 9, "Bb": 10, "B": 11,
}
TUNING = [4, 9, 2, 7, 11, 4]  # E A D G B e, pitch classes
QUALITIES = {
    "major": ("major", "Maior", {0, 4, 7}),
    "minor": ("minor", "Menor", {0, 3, 7}),
    "7": ("dominant_seventh", "7", {0, 4, 7, 10}),
    "sus2": ("sus2", "Sus2", {0, 2, 7}),
    "sus4": ("sus4", "Sus4", {0, 5, 7}),
    "dim": ("diminished", "Dim", {0, 3, 6}),
    "aug": ("augmented", "Aug", {0, 4, 8}),
}
OUTPUT = Path(__file__).resolve().parents[1] / "priv/repo/chords_db_guitar.json"


def absolute_frets(position):
    """chords-db uses E-to-e order and 1-based frets within baseFret."""
    base = position["baseFret"]
    return [None if fret == -1 else (0 if fret == 0 else base + fret - 1)
            for fret in position["frets"]]


def curate(source):
    if source["tunings"]["standard"] != ["E2", "A2", "D3", "G3", "B3", "E4"]:
        raise ValueError("Unexpected source tuning")

    shapes = []
    seen = set()
    rejected = []
    for key in ROOTS:
        for chord in source["chords"][key]:
            suffix = chord["suffix"]
            if suffix not in QUALITIES:
                continue
            quality, name, intervals = QUALITIES[suffix]
            root = ROOTS[key]
            expected = {(root + interval) % 12 for interval in intervals}
            for number, position in enumerate(chord["positions"], 1):
                frets = absolute_frets(position)
                if len(frets) != 6 or any(fret is not None and not 0 <= fret <= 24 for fret in frets):
                    rejected.append((key, suffix, number, "invalid fret"))
                    continue
                pitches = {(tuning + fret) % 12 for tuning, fret in zip(TUNING, frets)
                           if fret is not None}
                if pitches != expected:
                    rejected.append((key, suffix, number, "wrong pitch classes"))
                    continue
                signature = tuple(frets)
                if signature in seen:
                    continue
                seen.add(signature)

                # A root must occur in the voicing. Prefer the lowest root string.
                root_string = next(6 - index for index, fret in enumerate(frets)
                                   if fret is not None and (TUNING[index] + fret) % 12 == root)
                # An open string needs base 0. Closed positions use the lowest fret
                # as their fixed base, so diagrams show the correct neck window.
                sounding = [fret for fret in frets if fret is not None]
                base = 0 if 0 in sounding else min(sounding)
                shapes.append({
                    "slug": f"chords-db-{key.lower()}-{suffix.replace('7', 'seventh')}-{number}",
                    "name": name,
                    "quality": quality,
                    "root_string": root_string,
                    "movable": base > 0,
                    "min_base_fret": base,
                    "max_base_fret": base,
                    "relative_frets": [None if fret is None else fret - base
                                       for fret in reversed(frets)],
                    "source": f"{key}/{suffix} position {number}",
                })
    return shapes, rejected


def main():
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    with open(sys.argv[1], encoding="utf-8") as source_file:
        shapes, rejected = curate(json.load(source_file))
    lines = [json.dumps(shape, ensure_ascii=False, separators=(",", ":")) for shape in shapes]
    OUTPUT.write_text("[\n" + ",\n".join(lines) + "\n]\n", encoding="utf-8")
    print(f"{len(shapes)} distinct valid positions; {len(rejected)} invalid positions rejected")
    for rejection in rejected:
        print("rejected:", *rejection)


if __name__ == "__main__":
    main()
