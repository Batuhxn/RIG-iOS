#!/usr/bin/env python3
"""RiG Atelier offline lab: the avatar and the Garment Engine v1 templates, evaluated
with the same maths as the Swift runtime, plus geometry checks.

    atelier_lab.py check            geometry invariants over the body/template matrix
    atelier_lab.py winding          triangle winding vs outward direction per template

Needs numpy (and Pillow for previews). Mirrors:
- AvatarMorphEngine.positions(for:)   (morph weights; see SHAPES below)
- GarmentDeformer.mesh(for:...)       (binding, 2 Taubin steps, canonical normals)
"""
from __future__ import annotations

import struct
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
BODY = ROOT / "Support/Avatar/RIGAvatarBody.rigavatar"
GARMENTS = ROOT / "Support/Avatar/RIGGarments.rigarm"

sys.path.insert(0, str(Path(__file__).resolve().parent))
import preview_avatar as pa  # noqa: E402


def read_templates(path=GARMENTS):
    data = Path(path).read_bytes()
    assert data[:8] == b"RIGGARM1"
    o = 8
    (count,) = struct.unpack_from("<I", data, o); o += 4
    out = {}
    for _ in range(count):
        name = data[o:o + 32].rstrip(b"\0").decode(); o += 32
        version, n = struct.unpack_from("<II", data, o); o += 8
        rec = np.frombuffer(data, dtype=np.dtype([("i", "<u4", 3), ("f", "<f4", 7), ("twin", "<u4")]), count=n, offset=o)
        o += 44 * n
        lists = []
        for _ in range(3):
            (c,) = struct.unpack_from("<I", data, o); o += 4
            lists.append(np.frombuffer(data, "<u4", c, o).astype(np.int64)); o += 4 * c
        out[name] = {
            "version": version,
            "idx": rec["i"].astype(np.int64), "w": rec["f"][:, :2].astype(np.float64),
            "off": rec["f"][:, 2:5].astype(np.float64), "uv": rec["f"][:, 5:7].astype(np.float64),
            "canonical": rec["twin"].astype(np.int64),
            "front": lists[0].reshape(-1, 3), "back": lists[1].reshape(-1, 3), "hidden": lists[2],
        }
    return out


def vertex_normals(P, T):
    N = np.zeros_like(P)
    fn = np.cross(P[T[:, 1]] - P[T[:, 0]], P[T[:, 2]] - P[T[:, 0]])
    for k in range(3):
        np.add.at(N, T[:, k], fn)
    return N / (np.linalg.norm(N, axis=1, keepdims=True) + 1e-12)


def topology(t):
    n = len(t["idx"])
    can = t["canonical"]
    nb = [set() for _ in range(n)]
    uses = {}
    for T in (t["front"], t["back"]):
        for tri in T:
            c = [can[v] for v in tri]
            for k in range(3):
                a, b = c[k], c[(k + 1) % 3]
                nb[a].add(b); nb[b].add(a)
                key = (min(a, b), max(a, b))
                uses[key] = uses.get(key, 0) + 1
    boundary = np.zeros(n, bool)
    for (a, b), u in uses.items():
        if u == 1:
            boundary[a] = boundary[b] = True
    return [sorted(s) for s in nb], boundary


def deform(t, P, BN, smoothing=2, topo=None):
    i = t["idx"]
    wb, wc = t["w"][:, 0:1], t["w"][:, 1:2]
    wa = 1 - wb - wc
    pa_, pb, pc = P[i[:, 0]], P[i[:, 1]], P[i[:, 2]]
    q = wa * pa_ + wb * pb + wc * pc
    n = wa * BN[i[:, 0]] + wb * BN[i[:, 1]] + wc * BN[i[:, 2]]
    n /= np.linalg.norm(n, axis=1, keepdims=True) + 1e-12
    e1 = (pb - pa_) - np.sum((pb - pa_) * n, axis=1, keepdims=True) * n
    e1 /= np.linalg.norm(e1, axis=1, keepdims=True) + 1e-12
    e2 = np.cross(n, e1)
    out = q + t["off"][:, 0:1] * n + t["off"][:, 1:2] * e1 + t["off"][:, 2:3] * e2
    nb, boundary = topo or topology(t)
    can = t["canonical"]
    for _ in range(smoothing):
        for factor in (0.5, -0.53):
            moved = out.copy()
            for k in range(len(out)):
                if can[k] != k or boundary[k] or not nb[k]:
                    continue
                centre = out[nb[k]].mean(axis=0)
                moved[k] = out[k] + factor * (centre - out[k])
            dup = can != np.arange(len(out))
            moved[dup] = moved[can[dup]]
            out = moved
    return out


SHAPES = {}


def shapes(targets):
    """Silhouette presets are defined in Swift (AvatarStartingSilhouette); here the
    matrix uses the neutral body and the report's extreme body via raw targets."""
    return {"neutral": {}}


def check():
    P0, subs, targets = pa.read_asset(str(BODY))
    P0 = P0.astype(np.float64)
    body = subs["body"].astype(np.int64)
    BN = vertex_normals(P0, body)
    for name, t in read_templates().items():
        g = deform(t, P0, BN)
        T = np.concatenate([t["front"], t["back"]])
        fn = np.cross(g[T[:, 1]] - g[T[:, 0]], g[T[:, 2]] - g[T[:, 0]])
        area = np.linalg.norm(fn, axis=1) / 2
        print(name, "verts", len(g), "tris", len(T), "nan", int(np.isnan(g).sum()),
              "degenerate(<1e-8 m2)", int((area < 1e-8).sum()))


def winding():
    P0, subs, _ = pa.read_asset(str(BODY))
    P0 = P0.astype(np.float64)
    body = subs["body"].astype(np.int64)
    BN = vertex_normals(P0, body)
    for name, t in read_templates().items():
        g = deform(t, P0, BN)
        for label in ("front", "back"):
            T = t[label]
            fn = np.cross(g[T[:, 1]] - g[T[:, 0]], g[T[:, 2]] - g[T[:, 0]])
            # Outward reference: the binding's body normal at the first corner.
            ref = BN[t["idx"][T[:, 0], 0]]
            dots = np.sum(fn * ref, axis=1)
            print(f"{name:9s} {label}: {len(T):5d} tris, outward-wound {np.mean(dots > 0) * 100:5.1f}%")


if __name__ == "__main__":
    {"check": check, "winding": winding}[sys.argv[1]]()
