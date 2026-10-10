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


# AvatarControl -> morph targets (Sources/AvatarLab/Core/AvatarBodyShape.swift).
CONTROL_TARGETS = {
    "shoulders": "shoulders", "waist": "waist", "hips": "hips", "legLength": "leglength",
    "height": "height", "torsoLength": "torsolength", "bust": "bust", "underbust": "underbust",
    "stomach": "stomach", "seat": "seat", "thighs": "thighs", "armLength": "armlength",
    "upperArms": "upperarms", "overall": "fullness",
}

# AvatarStartingSilhouette.all plus the review grids' extreme body.
SHAPES = {
    "silhouette-1": {},
    "silhouette-2": {"waist": -0.4, "hips": 0.5, "seat": 0.4, "bust": 0.3, "shoulders": -0.2, "thighs": 0.3},
    "silhouette-3": {"shoulders": 0.5, "upperBody": 0.4, "waist": 0.2, "hips": -0.3, "bust": -0.6, "seat": -0.3},
    "extreme": {"hips": 1, "waist": -1, "bust": 1, "shoulders": 1, "overall": 0.8},
}


def target_weights(shape):
    w = {}
    for control, value in shape.items():
        if value == 0:
            continue
        side = "decr" if value < 0 else "incr"
        if control == "upperBody":
            parts = [("underbust", 1.0), ("bust", 0.5)]
        else:
            parts = [(CONTROL_TARGETS[control], 1.0)]
        for base, per in parts:
            key = f"{base}-{side}"
            w[key] = w.get(key, 0.0) + abs(value) * per
    return w


def morphed(P0, targets, shape):
    P = P0.copy()
    for name, weight in target_weights(shape).items():
        if name in targets:
            idx, d = targets[name]
            P[idx] += weight * d
    return P


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
    if sys.argv[1] in ("check", "winding"):
        {"check": check, "winding": winding}[sys.argv[1]]()


# --- closest-triangle signed distance (numpy + scipy KD-tree on centroids) ----------

def closest_points(p, a, b, c):
    """Vectorised Ericson closest point; p (N,3), a/b/c (N,3)."""
    ab, ac, ap = b - a, c - a, p - a
    d1, d2 = np.einsum("ij,ij->i", ab, ap), np.einsum("ij,ij->i", ac, ap)
    bp = p - b
    d3, d4 = np.einsum("ij,ij->i", ab, bp), np.einsum("ij,ij->i", ac, bp)
    cp = p - c
    d5, d6 = np.einsum("ij,ij->i", ab, cp), np.einsum("ij,ij->i", ac, cp)
    va, vb, vc = d3 * d6 - d5 * d4, d5 * d2 - d1 * d6, d1 * d4 - d3 * d2
    den = va + vb + vc
    den = np.where(np.abs(den) < 1e-30, 1e-30, den)
    out = a + ab * (vb / den)[:, None] + ac * (vc / den)[:, None]
    def put(mask, val):
        out[mask] = val[mask]
    with np.errstate(divide="ignore", invalid="ignore"):
        put((va <= 0) & (d4 - d3 >= 0) & (d5 - d6 >= 0), b + ((d4 - d3) / ((d4 - d3) + (d5 - d6)))[:, None] * (c - b))
        put((vb <= 0) & (d2 >= 0) & (d6 <= 0), a + (d2 / (d2 - d6))[:, None] * ac)
        put((d6 >= 0) & (d5 <= d6), c)
        put((vc <= 0) & (d1 >= 0) & (d3 <= 0), a + (d1 / (d1 - d3))[:, None] * ab)
        put((d3 >= 0) & (d4 <= d3), b)
        put((d1 <= 0) & (d2 <= 0), a)
    return out


def signed_distance(points, P, T, k=48):
    """Distance to the closest body triangle, negative behind its face. Returns
    (signed distance, triangle index, closest point)."""
    from scipy.spatial import cKDTree
    A, B, C = P[T[:, 0]], P[T[:, 1]], P[T[:, 2]]
    tree = cKDTree((A + B + C) / 3)
    _, cand = tree.query(points, k=k)
    n, m = cand.shape
    pr = np.repeat(points, m, axis=0)
    flat = cand.reshape(-1)
    q = closest_points(pr, A[flat], B[flat], C[flat])
    d = np.linalg.norm(pr - q, axis=1).reshape(n, m)
    best = d.argmin(axis=1)
    tri = cand[np.arange(n), best]
    qb = q.reshape(n, m, 3)[np.arange(n), best]
    fn = np.cross(B[tri] - A[tri], C[tri] - A[tri])
    fn /= np.linalg.norm(fn, axis=1, keepdims=True) + 1e-12
    s = np.sign(np.einsum("ij,ij->i", points - qb, fn))
    return s * d[np.arange(n), best], tri, qb


def penetration():
    P0, subs, targets = pa.read_asset(str(BODY))
    P0 = P0.astype(np.float64)
    body = subs["body"].astype(np.int64)
    T = body.reshape(-1, 3)
    for shape_name, shape in SHAPES.items():
        P = morphed(P0, targets, shape)
        BN = vertex_normals(P, T)
        for name, t in read_templates().items():
            g = deform(t, P, BN)
            sd, tri, _ = signed_distance(g, P, T)
            hidden = set(t["hidden"].tolist())
            visible = np.array([i not in hidden for i in tri])
            bad = (sd < -0.002) & visible
            worst = sd[visible].min() * 1000 if visible.any() else 0
            print(f"{shape_name:13s} {name:9s} inside>2mm on visible skin: {bad.sum():3d}  worst {worst:7.2f} mm")


if __name__ == "__main__" and sys.argv[1] == "penetration":
    penetration()


def skin_through(shapes=None, margin=0.001):
    """Visible skin poking out through a garment: body vertices of visible triangles whose
    closest garment point lies away from the garment's open edges, yet which sit
    outside the garment surface (by more than `margin`)."""
    from scipy.spatial import cKDTree
    P0, subs, targets = pa.read_asset(str(BODY))
    P0 = P0.astype(np.float64)
    T = subs["body"].astype(np.int64).reshape(-1, 3)
    for shape_name in (shapes or SHAPES):
        P = morphed(P0, targets, SHAPES[shape_name])
        BN = vertex_normals(P, T)
        for name, t in read_templates().items():
            g = deform(t, P, BN)
            F = np.concatenate([t["front"], t["back"]])
            nb, boundary = topology(t)
            edge = boundary[t["canonical"]]
            hidden = np.zeros(len(T), bool); hidden[t["hidden"]] = True
            vis = np.unique(T[~hidden].reshape(-1))
            near = cKDTree(g).query(P[vis], k=1)
            cand = vis[near[0] < 0.04]
            if len(cand) == 0:
                print(shape_name, name, 0); continue
            sd, tri, q = signed_distance(P[cand], g, F)
            # the closest garment face must not touch an open edge (necklines, hems, cuffs)
            interior = ~edge[F[tri]].any(axis=1)
            # also skip skin far from any garment vertex ring: require distance < 2 cm
            out = (sd > margin) & interior & (np.abs(sd) < 0.02)
            print(f"{shape_name:13s} {name:9s} visible skin outside the garment: {out.sum():4d}  worst {sd[out].max()*1000 if out.any() else 0:6.1f} mm", np.round(P[cand][out].mean(axis=0), 2) if out.any() else "")


if __name__ == "__main__" and sys.argv[1] == "skinthrough":
    skin_through()
