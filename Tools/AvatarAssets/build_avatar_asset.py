#!/usr/bin/env python3
"""Builds RIG's avatar body asset from MakeHuman's CC0 base mesh and targets.

Only MakeHuman *assets* are read (base mesh and .target morphs, CC0 1.0, see
LICENSE.ASSETS.md in the MakeHuman repository). No MakeHuman application code
(AGPL) is used, copied or linked: this script parses two plain text formats.

    python3 -I Tools/AvatarAssets/build_avatar_asset.py <download-dir> <output.rigavatar>

The download directory is filled from a pinned MakeHuman commit on first run and
every file is checked against SOURCES.lock.json afterwards, so the asset is
reproducible. Output is a little-endian binary read by AvatarAssetLoader.swift:

    "RIGAVTR1"            8 bytes magic
    u32 vertexCount
    f32 positions[3 * vertexCount]          metres, y up, feet at y = 0
    u32 submeshCount
      per submesh: 32-byte name, u32 indexCount, u32 indices[indexCount]  (triangles)
    u32 targetCount
      per target:  32-byte name, f32 scale, u32 count,
                   u32 vertex[count], i16 delta[3 * count]   (delta = i16 * scale, metres)
"""
from __future__ import annotations

import hashlib
import json
import struct
import sys
import urllib.request
from pathlib import Path

COMMIT = "a8bc2d54ff0ac92e78ff71431b1023eda42bf482"
RAW = f"https://raw.githubusercontent.com/makehumancommunity/makehuman/{COMMIT}/makehuman/data/"
HERE = Path(__file__).resolve().parent
LOCK = HERE / "SOURCES.lock.json"

ETHNICITIES = ["african", "asian", "caucasian"]

# Groups of base.obj that become submeshes. The helpers are MakeHuman's own
# clothing proxies: every target also moves them, so they follow the body.
SUBMESHES = {"body": "body", "helper-tights": "tights", "helper-skirt": "skirt"}

# Simple two-sided controls: (name, decrease target, increase target).
PAIRS = [
    ("shoulders", "measure/measure-shoulder-dist-decr", "measure/measure-shoulder-dist-incr"),
    ("bust", "measure/measure-bust-circ-decr", "measure/measure-bust-circ-incr"),
    ("underbust", "measure/measure-underbust-circ-decr", "measure/measure-underbust-circ-incr"),
    ("waist", "measure/measure-waist-circ-decr", "measure/measure-waist-circ-incr"),
    ("hips", "measure/measure-hips-circ-decr", "measure/measure-hips-circ-incr"),
    ("seat", "buttocks/buttocks-volume-decr", "buttocks/buttocks-volume-incr"),
    ("thighs", "measure/measure-thigh-circ-decr", "measure/measure-thigh-circ-incr"),
    ("upperarms", "measure/measure-upperarm-circ-decr", "measure/measure-upperarm-circ-incr"),
    ("torsolength", "measure/measure-napetowaist-dist-decr", "measure/measure-napetowaist-dist-incr"),
    ("stomach", "stomach/stomach-pregnant-decr", "stomach/stomach-pregnant-incr"),
]
# Controls that move two targets together.
COMBINED = [
    ("leglength", ["measure/measure-upperleg-height-{d}", "measure/measure-lowerleg-height-{d}"]),
    ("armlength", ["measure/measure-upperarm-length-{d}", "measure/measure-lowerarm-length-{d}"]),
]


def macro_paths() -> list[str]:
    paths = [f"macrodetails/{e}-{g}-young" for e in ETHNICITIES for g in ("female", "male")]
    paths += [f"macrodetails/universal-{g}-young-averagemuscle-{w}weight" for g in ("female", "male") for w in ("min", "max")]
    paths += [f"macrodetails/height/{g}-young-averagemuscle-averageweight-{h}height" for g in ("female", "male") for h in ("min", "max")]
    return paths


def all_sources() -> list[str]:
    files = ["3dobjs/base.obj"]
    for _, a, b in PAIRS:
        files += [f"targets/{a}.target", f"targets/{b}.target"]
    for _, parts in COMBINED:
        files += [f"targets/{p.format(d=d)}.target" for p in parts for d in ("decr", "incr")]
    files += [f"targets/{p}.target" for p in macro_paths()]
    return files


def fetch(download: Path) -> None:
    lock = json.loads(LOCK.read_text()) if LOCK.exists() else {}
    for rel in all_sources():
        dest = download / rel
        if not dest.exists():
            dest.parent.mkdir(parents=True, exist_ok=True)
            with urllib.request.urlopen(RAW + rel) as response:  # noqa: S310 - pinned https URL
                dest.write_bytes(response.read())
        digest = hashlib.sha256(dest.read_bytes()).hexdigest()
        if rel in lock and lock[rel] != digest:
            sys.exit(f"{rel}: sha256 {digest} does not match SOURCES.lock.json")
        lock[rel] = digest
    LOCK.write_text(json.dumps({"commit": COMMIT, **{k: v for k, v in sorted(lock.items()) if k != "commit"}}, indent=1) + "\n")


def read_obj(path: Path):
    positions, faces = [], {}
    group = None
    for line in path.read_text().splitlines():
        if line.startswith("v "):
            positions.append([float(x) for x in line.split()[1:4]])
        elif line.startswith("g "):
            group = line.split()[1]
        elif line.startswith("f ") and group in SUBMESHES:
            idx = [int(tok.split("/")[0]) - 1 for tok in line.split()[1:]]
            faces.setdefault(group, []).append(idx)
    return positions, faces


def read_target(path: Path) -> dict[int, tuple[float, float, float]]:
    out = {}
    for line in path.read_text().splitlines():
        parts = line.split()
        if len(parts) == 4 and not line.startswith("#"):
            out[int(parts[0])] = (float(parts[1]), float(parts[2]), float(parts[3]))
    return out


def combine(download: Path, weighted: list[tuple[str, float]]) -> dict[int, list[float]]:
    acc: dict[int, list[float]] = {}
    for rel, weight in weighted:
        for i, (x, y, z) in read_target(download / "targets" / f"{rel}.target").items():
            a = acc.setdefault(i, [0.0, 0.0, 0.0])
            a[0] += weight * x
            a[1] += weight * y
            a[2] += weight * z
    return acc


# Mannequin look: anatomical detail (face, nipples, pelvis) is smoothed away in the
# rest pose so the avatar reads as a dress form, not a person. Regions are in
# output metres of the neutral figure: (name, test, iterations, shrink-back factor).
# A shrink-back of -0.53 is Taubin smoothing (keeps volume, softens bumps); 0 is
# plain Laplacian, used on the face so its features fade to a dress-form head.
SMOOTH_REGIONS = [
    ("face", lambda x, y, z: y > 1.50 and z > 0.02, 14, 0.0),
    ("chest", lambda x, y, z: 1.12 < y < 1.32 and z > 0.0 and abs(x) < 0.16, 10, -0.53),
    ("pelvis", lambda x, y, z: 0.70 < y < 0.88 and abs(x) < 0.09 and z > -0.02, 12, -0.53),
]


def mannequin_smooth(points, faces, scale, floor):
    """Taubin smoothing (no shrinkage) restricted to SMOOTH_REGIONS, with a
    soft edge so smoothed and untouched areas meet without a seam."""
    n = len(points)
    neighbours = [set() for _ in range(n)]
    for f in faces:
        for k in range(len(f)):
            a, b = f[k], f[(k + 1) % len(f)]
            neighbours[a].add(b)
            neighbours[b].add(a)
    pts = [list(p) for p in points]
    out_m = lambda p: (p[0] * scale, (p[1] - floor) * scale, p[2] * scale)
    for _, test, iterations, shrink_back in SMOOTH_REGIONS:
        inside = [bool(neighbours[i]) and test(*out_m(pts[i])) for i in range(n)]
        # Weight 1 inside, fading to 0 over two rings of neighbours outside.
        weight = [1.0 if inside[i] else 0.0 for i in range(n)]
        for fade in (0.5, 0.2):
            ring = [i for i in range(n) if weight[i] == 0 and any(weight[j] > fade for j in neighbours[i])]
            for i in ring:
                weight[i] = fade
        active = [i for i in range(n) if weight[i] > 0]
        for _ in range(iterations):
            for factor in (0.5, shrink_back) if shrink_back else (0.5,):
                moved = {}
                for i in active:
                    nb = neighbours[i]
                    c = [sum(pts[j][k] for j in nb) / len(nb) for k in range(3)]
                    moved[i] = [pts[i][k] + factor * weight[i] * (c[k] - pts[i][k]) for k in range(3)]
                for i, p in moved.items():
                    pts[i] = p
    return pts


def main() -> int:
    download, output = Path(sys.argv[1]), Path(sys.argv[2])
    fetch(download)
    positions, faces = read_obj(download / "3dobjs" / "base.obj")

    third = 1.0 / len(ETHNICITIES)
    female = [(f"macrodetails/{e}-female-young", third) for e in ETHNICITIES]
    male = [(f"macrodetails/{e}-male-young", third) for e in ETHNICITIES]

    # MakeHuman's default human is the base mesh with gender 0.5 and age 25: half
    # of each young macro. That neutral figure is baked into the positions.
    neutral = combine(download, [(p, 0.5 * w) for p, w in female + male])
    for i, d in neutral.items():
        for k in range(3):
            positions[i][k] += d[k]

    targets: list[tuple[str, dict[int, list[float]]]] = []
    # "frame": the remaining half of either macro, so -1 and +1 are its two ends.
    targets.append(("frame-a", combine(download, [(p, 0.5 * w) for p, w in female] + [(p, -0.5 * w) for p, w in male])))
    targets.append(("frame-b", combine(download, [(p, 0.5 * w) for p, w in male] + [(p, -0.5 * w) for p, w in female])))
    for side, w in (("decr", "min"), ("incr", "max")):
        targets.append((f"fullness-{side}", combine(download, [(f"macrodetails/universal-{g}-young-averagemuscle-{w}weight", 0.5) for g in ("female", "male")])))
        h = "min" if side == "decr" else "max"
        targets.append((f"height-{side}", combine(download, [(f"macrodetails/height/{g}-young-averagemuscle-averageweight-{h}height", 0.5) for g in ("female", "male")])))
    for name, a, b in PAIRS:
        targets.append((f"{name}-decr", combine(download, [(a, 1.0)])))
        targets.append((f"{name}-incr", combine(download, [(b, 1.0)])))
    for name, parts in COMBINED:
        for d in ("decr", "incr"):
            targets.append((f"{name}-{d}", combine(download, [(p.format(d=d), 1.0) for p in parts])))

    # Keep only vertices used by a kept submesh, and re-index.
    used = sorted({i for fs in faces.values() for f in fs for i in f})
    remap = {old: new for new, old in enumerate(used)}
    scale = 0.1  # MakeHuman units are decimetres
    kept = [positions[i] for i in used]
    floor = min(p[1] for p in kept)

    kept = mannequin_smooth(kept, [[remap[i] for i in f] for f in faces["body"]], scale, floor)

    blob = bytearray(b"RIGAVTR1")
    blob += struct.pack("<I", len(kept))
    for x, y, z in kept:
        blob += struct.pack("<3f", x * scale, (y - floor) * scale, z * scale)
    blob += struct.pack("<I", len(SUBMESHES))
    stats = {}
    for group, name in SUBMESHES.items():
        tris = []
        for f in faces.get(group, []):
            for k in range(1, len(f) - 1):
                tris += [remap[f[0]], remap[f[k]], remap[f[k + 1]]]
        blob += name.encode().ljust(32, b"\0") + struct.pack("<I", len(tris)) + struct.pack(f"<{len(tris)}I", *tris)
        stats[name] = len(tris) // 3
    blob += struct.pack("<I", len(targets))
    target_stats = {}
    for name, deltas in targets:
        entries = sorted((remap[i], d) for i, d in deltas.items() if i in remap and max(abs(c) for c in d) > 1e-6)
        peak = max((abs(c) for _, d in entries for c in d), default=0.0) * scale
        q = peak / 32767 if peak > 0 else 1.0
        blob += name.encode().ljust(32, b"\0") + struct.pack("<fI", q, len(entries))
        blob += struct.pack(f"<{len(entries)}I", *[i for i, _ in entries])
        blob += struct.pack(f"<{3 * len(entries)}h", *[round(c * scale / q) for _, d in entries for c in d])
        target_stats[name] = {"vertices": len(entries), "peak_m": round(peak, 4)}

    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(bytes(blob))
    height = (max(p[1] for p in kept) - floor) * scale
    print(json.dumps({"bytes": len(blob), "vertices": len(kept), "triangles": stats, "height_m": round(height, 3), "targets": target_stats}, indent=1))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
