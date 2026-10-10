#!/usr/bin/env python3
"""Independent, offline RiG geometry audit. Requires only numpy (plus stdlib).

Run from any directory: python -B Tools/AvatarAssets/audit_garment_geometry.py
Use --self-test to validate the distance/inside kernels; --json for full evidence;
--strict returns 1 for penetration >2 mm, degenerate faces or inward faces.
No assets, reports or source files are written. Runtime math uses float32;
distance queries use float64 and ALL body triangles, with exact AABB pruning.

Inside means majority parity of three non-axis-aligned rays through the FULL
body (before hidden-skin removal). Depth is Euclidean nearest-triangle distance,
not a nearest-vertex tangent-plane estimate. Open/nonmanifold body edges and ray
disagreements are reported so the limitations of solid classification are visible.
Flipped faces use the runtime's global orientation correction and compare each
face to the mean of its three binding normals (local outward, also for limbs).
Rest edge lengths use the neutral garment with the SAME smoothing setting.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import struct
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
PRESETS = {
    "silhouette-1": {},
    "silhouette-2": {"waist": -.4, "hips": .5, "seat": .4, "bust": .3,
                     "shoulders": -.2, "thighs": .3},
    "silhouette-3": {"shoulders": .5, "upperBody": .4, "waist": .2,
                     "hips": -.3, "bust": -.6, "seat": -.3},
    # Same extreme as GarmentEngineTests.testExtremeButValidShapesKeepGarmentsOutsideTheSkin.
    "extreme": {"hips": 1, "waist": -1, "bust": 1, "shoulders": 1,
                "overall": 1, "legLength": -.6},
}
ALIASES = {"legLength": "leglength", "torsoLength": "torsolength",
           "armLength": "armlength", "upperArms": "upperarms", "overall": "fullness"}
RECORD = np.dtype([("body", "<u4", (3,)), ("weights", "<f4", (2,)),
                   ("offset", "<f4", (3,)), ("uv", "<f4", (2,)), ("canonical", "<u4")])
AREA_EPS = 1e-10  # m²: twice-area below this is numerically degenerate.


class Reader:
    def __init__(self, path, magic):
        self.data = Path(path).read_bytes()
        self.offset = 0
        if self.take(8) != magic:
            raise ValueError(f"{path}: bad magic")

    def take(self, n):
        if n < 0 or n > len(self.data) - self.offset:
            raise ValueError("truncated asset")
        start = self.offset
        self.offset += n
        return self.data[start:self.offset]

    def u32(self):
        return struct.unpack("<I", self.take(4))[0]

    def name(self):
        return self.take(32).split(b"\0", 1)[0].decode("utf-8")

    def array(self, dtype, count):
        return np.frombuffer(self.take(np.dtype(dtype).itemsize * count), dtype).copy()

    def done(self):
        if self.offset != len(self.data):
            raise ValueError("trailing asset bytes")


def read_body(path):
    r = Reader(path, b"RIGAVTR1")
    p = r.array("<f4", r.u32() * 3).reshape(-1, 3)
    if not np.isfinite(p).all() or np.abs(p).max(initial=0) > 10:
        raise ValueError("invalid body positions")
    subs = {}
    for _ in range(r.u32()):
        name = r.name()
        t = r.array("<u4", r.u32())
        if len(t) % 3 or (t >= len(p)).any():
            raise ValueError("invalid body triangles")
        subs[name] = t.reshape(-1, 3)
    targets = {}
    for _ in range(r.u32()):
        name = r.name()
        scale = struct.unpack("<f", r.take(4))[0]
        n = r.u32()
        ids = r.array("<u4", n)
        delta = r.array("<i2", n * 3).reshape(-1, 3).astype(np.float32) * np.float32(scale)
        if (ids >= len(p)).any() or not np.isfinite(scale) or not 0 < scale <= 10 / 32767:
            raise ValueError("invalid morph")
        targets[name] = (ids, delta)
    r.done()
    for name in ("body", "tights", "skirt"):
        if name not in subs:
            raise ValueError(f"missing submesh {name}")
    return p, subs, targets


def read_garments(path, vertex_count, triangle_count):
    r = Reader(path, b"RIGGARM1")
    garments = {}
    count = r.u32()
    if count > 64:
        raise ValueError("invalid template count")
    for _ in range(count):
        name, version, n = r.name(), r.u32(), r.u32()
        rec = r.array(RECORD, n)
        if version != 1 or (rec["body"] >= vertex_count).any() or (rec["canonical"] >= n).any():
            raise ValueError("invalid binding index/version")
        for field in ("weights", "offset", "uv"):
            if not np.isfinite(rec[field]).all() or (np.abs(rec[field]) > 10).any():
                raise ValueError("invalid binding value")
        if (rec["weights"] < -1e-6).any() or (rec["weights"].sum(axis=1) > 1 + 1e-6).any():
            raise ValueError("weights outside barycentric simplex")
        canonical = rec["canonical"].astype(np.int64)
        if not np.array_equal(canonical[canonical], canonical):
            raise ValueError("non-root canonical mapping")
        lists = []
        for limit in (n, n, triangle_count):
            values = r.array("<u4", r.u32())
            if (values >= limit).any():
                raise ValueError("invalid triangle/hidden index")
            lists.append(values)
        if any(len(v) % 3 for v in lists[:2]):
            raise ValueError("partial triangle")
        front, back = (v.reshape(-1, 3) for v in lists[:2])
        triangles = np.concatenate((front, back))
        ct = canonical[triangles]
        edges = np.sort(np.concatenate((ct[:, [0, 1]], ct[:, [1, 2]], ct[:, [2, 0]])), axis=1)
        unique, uses = np.unique(edges, axis=0, return_counts=True)
        boundary = np.zeros(n, bool)
        boundary[unique[uses == 1].ravel()] = True
        neighbours = [set() for _ in range(n)]
        for a, b in unique:
            neighbours[a].add(int(b))
            neighbours[b].add(int(a))
        garments[name] = dict(rec=rec, canonical=canonical, front=front, triangles=triangles,
                              hidden=lists[2], boundary=boundary,
                              neighbours=[np.array(sorted(v), np.int64) for v in neighbours],
                              edges=np.unique(np.sort(np.concatenate((triangles[:, [0, 1]],
                                      triangles[:, [1, 2]], triangles[:, [2, 0]])), axis=1), axis=0))
    r.done()
    return garments


def normalized(v, fallback=None):
    lengths = np.sqrt(np.sum(v * v, axis=-1, keepdims=True))
    good = lengths > (0 if fallback is None else 1e-12)
    out = v / np.where(good, lengths, 1)
    return np.where(good, out, 0 if fallback is None else fallback)


def vertex_normals(p, triangles, canonical=None):
    acc = np.zeros_like(p)
    fn = np.cross(p[triangles[:, 1]] - p[triangles[:, 0]], p[triangles[:, 2]] - p[triangles[:, 0]])
    ids = triangles if canonical is None else canonical[triangles]
    for k in range(3):
        np.add.at(acc, ids[:, k], fn)
    return acc


def morph(rest, targets, controls):
    weights = {}
    for control, value in controls.items():
        lo, hi = (-.6, .35) if control == "height" else ((-.6, .6) if control in
                  ("legLength", "torsoLength", "armLength") else (-1, 1))
        value = min(max(value, lo), hi)
        bases = [("underbust", 1), ("bust", .5)] if control == "upperBody" else [(ALIASES.get(control, control), 1)]
        for base, factor in bases:
            key = base + ("-decr" if value < 0 else "-incr")
            weights[key] = weights.get(key, np.float32(0)) + np.float32(abs(value) * factor)
    p = rest.copy()
    # Swift dictionary order is unspecified; float32 last-bit differences are possible.
    for key, weight in weights.items():
        ids, delta = targets[key]  # Fail loudly if a requested target is missing.
        np.add.at(p, ids, weight * delta)
    return p


def deform(g, body, normals, smoothing):
    rec, canonical = g["rec"], g["canonical"]
    weights = np.column_stack((1 - rec["weights"][:, 0] - rec["weights"][:, 1], rec["weights"]))
    a, b, c = (body[rec["body"][:, k]] for k in range(3))
    q = weights[:, :1] * a + weights[:, 1:2] * b + weights[:, 2:] * c
    n = normalized(np.sum(weights[:, :, None] * normals[rec["body"]], axis=1), [0, 0, 1]).astype(np.float32)
    e = b - a
    e = e - np.sum(e * n, axis=1, keepdims=True) * n
    bad_frames = int(np.count_nonzero(np.linalg.norm(e, axis=1) <= 1e-12))
    e1 = normalized(e, [0, 0, 1]).astype(np.float32)
    e2 = np.cross(n, e1)
    offset = rec["offset"]
    p = q + offset[:, :1] * n + offset[:, 1:2] * e1 + offset[:, 2:] * e2
    raw = p.copy()
    active = np.flatnonzero((canonical == np.arange(len(p))) & ~g["boundary"])
    for _ in range(smoothing):
        for factor in (.5, -.53):
            moved = p.copy()
            for k in active:
                ring = g["neighbours"][k]
                if len(ring):
                    moved[k] = p[k] + np.float32(factor) * (p[ring].mean(axis=0) - p[k])
            p = moved[canonical]
    acc = vertex_normals(p, g["triangles"], canonical)
    score = np.sum(acc[canonical] * normals[rec["body"][:, 0]])
    flip = -1 if score < 0 else 1
    shading = flip * normalized(acc[canonical], [0, 0, 1])
    return p, raw, n, shading, flip, bad_frames


def closest_on_triangles(point, vertices):
    """Exact closest point to each triangle, including collapsed triangles."""
    a, b, c = vertices[:, 0], vertices[:, 1], vertices[:, 2]
    ab, ac = b - a, c - a
    fn = np.cross(ab, ac)
    nn = np.sum(fn * fn, axis=1)
    projected = point - (np.sum((point - a) * fn, axis=1) / np.where(nn > 0, nn, 1))[:, None] * fn
    d00, d01, d11 = np.sum(ab * ab, axis=1), np.sum(ab * ac, axis=1), np.sum(ac * ac, axis=1)
    ap = projected - a
    d20, d21 = np.sum(ap * ab, axis=1), np.sum(ap * ac, axis=1)
    denom = d00 * d11 - d01 * d01
    wb = (d11 * d20 - d01 * d21) / np.where(denom > 0, denom, 1)
    wc = (d00 * d21 - d01 * d20) / np.where(denom > 0, denom, 1)
    interior = (denom > 0) & (wb >= 0) & (wc >= 0) & (wb + wc <= 1)
    best = projected.copy()
    distance = np.where(interior, np.sum((point - projected) ** 2, axis=1), np.inf)
    for start, end in ((a, b), (b, c), (c, a)):
        edge = end - start
        length = np.sum(edge * edge, axis=1)
        t = np.clip(np.sum((point - start) * edge, axis=1) / np.where(length > 0, length, 1), 0, 1)
        q = start + t[:, None] * edge
        ds = np.sum((point - q) ** 2, axis=1)
        update = ds < distance
        best[update], distance[update] = q[update], ds[update]
    return best, distance


class Surface:
    def __init__(self, p, triangles):
        self.vertices = p.astype(np.float64)[triangles]
        self.lo, self.hi = self.vertices.min(axis=1), self.vertices.max(axis=1)
        self.centres = self.vertices.mean(axis=1)
        self.rays = []
        for direction in ([1, .371, .529], [.293, 1, .617], [.419, .233, 1]):
            direction = normalized(np.array(direction, float))
            u = normalized(np.cross(direction, [0, 0, 1]))
            rotation = np.column_stack((direction, u, np.cross(direction, u)))
            v = self.vertices @ rotation
            self.rays.append((rotation, v, v.min(axis=1), v.max(axis=1)))

    def nearest(self, points):
        distances, ids, closest = [], [], []
        for point in points.astype(np.float64):
            upper = np.min(np.sum((self.centres - point) ** 2, axis=1))
            lower = np.sum(np.maximum(np.maximum(self.lo - point, point - self.hi), 0) ** 2, axis=1)
            candidates = np.flatnonzero(lower <= upper + 1e-15)
            q, d = closest_on_triangles(point, self.vertices[candidates])
            k = int(np.argmin(d))
            distances.append(np.sqrt(d[k]))
            ids.append(int(candidates[k]))
            closest.append(q[k])
        return np.array(distances), np.array(ids), np.array(closest)

    def inside(self, points):
        votes = np.zeros(len(points), np.int32)
        for rotation, vertices, lo, hi in self.rays:
            for k, point in enumerate(points.astype(np.float64) @ rotation):
                cand = ((lo[:, 1] <= point[1]) & (hi[:, 1] >= point[1]) &
                        (lo[:, 2] <= point[2]) & (hi[:, 2] >= point[2]) & (hi[:, 0] > point[0]))
                t = vertices[cand]
                if not len(t):
                    continue
                a, ab, ac = t[:, 0], t[:, 1] - t[:, 0], t[:, 2] - t[:, 0]
                den = ab[:, 1] * ac[:, 2] - ab[:, 2] * ac[:, 1]
                valid = np.abs(den) > 1e-15
                dy, dz = point[1] - a[:, 1], point[2] - a[:, 2]
                safe = np.where(valid, den, 1)
                wb = (dy * ac[:, 2] - dz * ac[:, 1]) / safe
                wc = (ab[:, 1] * dz - ab[:, 2] * dy) / safe
                hit = a[:, 0] + wb * ab[:, 0] + wc * ac[:, 0] - point[0]
                hits = np.sort(hit[valid & (wb >= 0) & (wc >= 0) & (wb + wc <= 1) & (hit > 1e-10)])
                # Shared-edge/vertex hits count once, avoiding parity double-counting.
                count = int(len(hits) > 0) + int(np.count_nonzero(np.diff(hits) > 1e-9))
                votes[k] += count % 2
        return votes >= 2, int(np.count_nonzero((votes != 0) & (votes != 3)))


def topology(triangles):
    edges = np.sort(np.concatenate((triangles[:, [0, 1]], triangles[:, [1, 2]], triangles[:, [2, 0]])), axis=1)
    _, uses = np.unique(edges, axis=0, return_counts=True)
    return {"open_edges": int(np.count_nonzero(uses == 1)), "nonmanifold_edges": int(np.count_nonzero(uses > 2))}


def self_test():
    triangle = np.array([[[0., 0, 0], [1, 0, 0], [0, 1, 0]]])
    for point, expected in (([.2, .3, 2], 4), ([2, 0, 0], 1), ([-1, -1, 0], 2)):
        _, ds = closest_on_triangles(np.array(point), triangle)
        np.testing.assert_allclose(ds, [expected])
    collapsed = np.zeros((1, 3, 3))
    np.testing.assert_allclose(closest_on_triangles(np.array([0, 0, 2]), collapsed)[1], [4])
    cube = np.array([[0, 0, 0], [1, 0, 0], [1, 1, 0], [0, 1, 0],
                     [0, 0, 1], [1, 0, 1], [1, 1, 1], [0, 1, 1]], float)
    tris = np.array([[0, 2, 1], [0, 3, 2], [4, 5, 6], [4, 6, 7], [0, 1, 5], [0, 5, 4],
                     [3, 7, 6], [3, 6, 2], [0, 4, 7], [0, 7, 3], [1, 2, 6], [1, 6, 5]])
    surface = Surface(cube, tris)
    points = np.array([[.5, .5, .5], [2, .5, .5], [.999, .2, .3], [-.1, .2, .3]])
    np.testing.assert_array_equal(surface.inside(points)[0], [True, False, True, False])
    np.testing.assert_allclose(surface.nearest(points)[0], [.5, 1, .001, .1], atol=1e-12)
    rng = np.random.default_rng(17)
    points = rng.uniform(-.5, 1.5, (100, 3))
    np.testing.assert_array_equal(surface.inside(points)[0], ((points > 0) & (points < 1)).all(axis=1))
    for point, measured in zip(points, surface.nearest(points)[0]):
        _, exhaustive = closest_on_triangles(point, cube[tris])
        np.testing.assert_allclose(measured, np.sqrt(exhaustive.min()), atol=1e-12)
    # Hand-derived binding reconstruction and right-handed tangent frame.
    rec = np.zeros(1, RECORD)
    rec["body"] = [0, 1, 2]
    rec["weights"] = [.2, .3]
    rec["offset"] = [.01, .02, .04]
    g = dict(rec=rec, canonical=np.array([0]), boundary=np.array([True]),
             neighbours=[np.array([], int)], triangles=np.zeros((0, 3), int))
    body = np.array([[0, 0, 0], [1, 0, 0], [0, 1, 0]], np.float32)
    normals = np.tile(np.array([0, 0, 1], np.float32), (3, 1))
    np.testing.assert_allclose(deform(g, body, normals, 0)[0], [[.22, .34, .01]], atol=1e-7)
    targets = {"underbust-incr": (np.array([0]), np.array([[1, 0, 0]], np.float32)),
               "bust-incr": (np.array([0]), np.array([[0, 0, 1]], np.float32)),
               "bust-decr": (np.array([0]), np.array([[0, 0, -1]], np.float32))}
    np.testing.assert_allclose(morph(np.zeros((1, 3), np.float32), targets,
                                    {"upperBody": .4, "bust": -.6}), [[.4, 0, -.4]], atol=1e-7)
    print("Self-test: distance, collapsed triangles, parity, AABB pruning, binding and morph weights passed.", file=sys.stderr)


def audit(body_path, garment_path, smoothing):
    rest, subs, targets = read_body(body_path)
    body_triangles = subs["body"]
    garments = read_garments(garment_path, len(rest), len(body_triangles))
    rest_normals = normalized(vertex_normals(rest, body_triangles))
    neutral = {name: deform(g, rest, rest_normals, smoothing)[0] for name, g in garments.items()}
    result = dict(body_sha256=hashlib.sha256(Path(body_path).read_bytes()).hexdigest(),
                  garments_sha256=hashlib.sha256(Path(garment_path).read_bytes()).hexdigest(),
                  smoothing=smoothing, controls=PRESETS, body_topology=topology(body_triangles), results=[])
    for preset, controls in PRESETS.items():
        body = morph(rest, targets, controls)
        normals = normalized(vertex_normals(body, body_triangles))
        surface = Surface(body, body_triangles)
        for name, g in garments.items():
            print(f"Auditing {preset} / {name}", file=sys.stderr, flush=True)
            p, raw, binding_n, shading, flip, bad_frames = deform(g, body, normals, smoothing)
            finite = np.isfinite(p).all(axis=1)
            if not finite.all():
                raise ValueError(f"{preset}/{name}: {int((~finite).sum())} nonfinite vertices; cannot measure geometry")
            distances, nearest, closest = surface.nearest(p)
            inside, disagreement = surface.inside(p)
            penetrated = inside & (distances > .002)
            t = g["triangles"]
            fn = np.cross(p[t[:, 1]] - p[t[:, 0]], p[t[:, 2]] - p[t[:, 0]])
            areas = np.linalg.norm(fn, axis=1)
            valid = areas > AREA_EPS
            outward = binding_n[t].mean(axis=1)
            dot = np.sum(flip * normalized(fn) * normalized(outward), axis=1)
            edges = g["edges"]
            rest_length = np.linalg.norm(neutral[name][edges[:, 1]] - neutral[name][edges[:, 0]], axis=1)
            length = np.linalg.norm(p[edges[:, 1]] - p[edges[:, 0]], axis=1)
            stretch = length[rest_length > 1e-10] / rest_length[rest_length > 1e-10]
            unique = g["canonical"] == np.arange(len(p))
            # Evidence includes worst body face and whether the static mask removes it.
            worst = int(np.argmax(np.where(inside, distances, 0)))
            front_fn = flip * normalized(fn[:len(g["front"])])
            result["results"].append(dict(preset=preset, template=name, vertices=len(p), triangles=len(t),
                nonfinite_vertices=int((~finite).sum()), degenerate_triangles=int((~valid).sum()),
                flipped_faces=int(np.count_nonzero(valid & (dot < -1e-6))),
                runtime_orientation_flip=flip, bad_binding_frames=bad_frames,
                binding_degenerate_triangles=int(np.count_nonzero(np.linalg.norm(np.cross(
                    body[g["rec"]["body"][:, 1]] - body[g["rec"]["body"][:, 0]],
                    body[g["rec"]["body"][:, 2]] - body[g["rec"]["body"][:, 0]]), axis=1) <= AREA_EPS)),
                penetration_vertices=int(penetrated.sum()), penetration_pct=float(penetrated.mean() * 100),
                unique_penetration_pct=float(penetrated[unique].mean() * 100),
                max_penetration_mm=float(np.max(np.where(inside, distances, 0), initial=0) * 1000),
                nearest_unhidden_penetrations=int(np.count_nonzero(penetrated & ~np.isin(nearest, g["hidden"]))),
                ray_disagreements=disagreement, edge_stretch_min=float(stretch.min()), edge_stretch_max=float(stretch.max()),
                zero_rest_edges=int(np.count_nonzero(rest_length <= 1e-10)),
                max_smoothing_move_mm=float(np.linalg.norm(p - raw, axis=1).max(initial=0) * 1000),
                front_faces_below_rest_facing_threshold=int(np.count_nonzero(front_fn[:, 2] < .35)),
                shading_normals_inward=int(np.count_nonzero(np.sum(shading * binding_n, axis=1) < 0)),
                worst_vertex=worst, worst_nearest_body_face=int(nearest[worst]),
                worst_nearest_face_hidden=bool(np.isin(nearest[worst], g["hidden"])),
                worst_position_m=p[worst].tolist(), worst_closest_body_m=closest[worst].tolist()))
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--body", type=Path, default=ROOT / "Support/Avatar/RIGAvatarBody.rigavatar")
    parser.add_argument("--garments", type=Path, default=ROOT / "Support/Avatar/RIGGarments.rigarm")
    parser.add_argument("--smoothing", type=int, choices=range(0, 11), default=2)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--strict", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return 0
    result = audit(args.body, args.garments, args.smoothing)
    if args.json:
        print(json.dumps(result, indent=2, allow_nan=False))
    else:
        print(f"Body topology: {result['body_topology']}; Taubin iterations: {args.smoothing}")
        print("Preset        Template    V     T  NaN Deg Flip  Inside>2mm    Max mm   Edge stretch")
        for r in result["results"]:
            print(f"{r['preset']:13} {r['template']:9} {r['vertices']:4} {r['triangles']:5} "
                  f"{r['nonfinite_vertices']:3} {r['degenerate_triangles']:3} {r['flipped_faces']:4} "
                  f"{r['penetration_pct']:10.2f}% {r['max_penetration_mm']:9.2f} "
                  f"{r['edge_stretch_min']:.3f}..{r['edge_stretch_max']:.3f}")
        print("SHA256 body:", result["body_sha256"])
        print("SHA256 garments:", result["garments_sha256"])
        print("Inside: 3-ray majority, full body; flip: relative to local binding outward after global correction.")
        print("Ray disagreements:", sum(r["ray_disagreements"] for r in result["results"]))
    defects = any(r["nonfinite_vertices"] or r["degenerate_triangles"] or r["flipped_faces"] or
                  r["penetration_vertices"] for r in result["results"])
    return 1 if args.strict and defects else 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (ValueError, OSError, KeyError) as error:
        print(f"Audit error: {error}", file=sys.stderr)
        sys.exit(2)
