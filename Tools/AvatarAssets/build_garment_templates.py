#!/usr/bin/env python3
"""Builds RiG Garment Engine v1 templates from the avatar asset.

    python3 -I Tools/AvatarAssets/build_garment_templates.py \
        Support/Avatar/RIGAvatarBody.rigavatar Support/Avatar/RIGGarments.rigarm [preview-dir]

Every template is authored here, from MakeHuman's CC0 helper-tights and
helper-skirt topology, so no third-party garment asset is distributed:

1. Cut: choose helper faces by rest-pose landmarks (whole quads).
2. Shape: give the cut its own volume at the rest pose. Cross-sections are
   convexified (no hollows under the chest or at the small of the back), then
   eased out; tops hang from the chest, skirts flare from the hips, trouser
   legs fall straight from the knee. The displacement is smoothed over the
   mesh so the shaped regions meet without folds.
3. Panels: faces are split at the side seams into a front panel (which gets
   the garment photo) and a back panel (an explicitly unknown region).
3b. Clear and unfold: garment vertices left inside the skin (the armholes cut
   into the arm root at the armpit; Atelier review) are moved just outside it,
   along the closest skin face's normal, and creases where the fabric folds
   back over itself (armpits, crotch: neighbouring faces more than 75 degrees
   apart) are relaxed, alternating until both hold, before binding.
4. Bind (.mhclo-style, implemented independently): each garment vertex is
   tied to its nearest body triangle by barycentric weights plus an offset in
   that triangle's local frame, so it follows every body morph.
5. Hide: body triangles that lie under the garment are listed, so the
   renderer can drop them and skin never pokes through.

Output (little-endian), read by GarmentTemplateLibrary.swift:

    "RIGGARM1" | u32 templateCount
    per template:
      32-byte name | u32 version | u32 V
      V × (u32 a, u32 b, u32 c,  f32 wb, f32 wc,  f32 dn, f32 t1, f32 t2,  f32 u, f32 v,  u32 canonical)  = 44 bytes
      u32 nFront | u32 × nFront      (triangle indices into the template's vertices)
      u32 nBack  | u32 × nBack
      u32 nHidden | u32 × nHidden    (indices of body triangles, i.e. body triangle list / 3)
"""
from __future__ import annotations

import json
import struct
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import preview_avatar as pa  # noqa: E402

VERSION = 1

# Rest-pose landmarks of the neutral figure (metres, feet at 0, A-pose).
NECK = 1.40
TORSO_X = 0.19
CROTCH = 0.80
WAIST = 0.99


def quads(tris):
    """Groups a triangle list into faces: consecutive fan pairs become quads."""
    faces, t = [], 0
    while t + 2 < len(tris):
        if t + 5 < len(tris) and tris[t + 3] == tris[t] and tris[t + 4] == tris[t + 2]:
            faces.append(list(tris[t:t + 6]))
            t += 6
        else:
            faces.append(list(tris[t:t + 3]))
            t += 3
    return faces


def select(P, tris, keep):
    out = []
    for f in quads(tris):
        c = P[list(dict.fromkeys(f))].mean(axis=0)
        if keep(c):
            out += f
    return out


def cross2(a, b):
    return a[0] * b[1] - a[1] * b[0]


def hull(points):
    """2D convex hull (monotone chain) of an (n, 2) array, counter-clockwise."""
    pts = sorted(set(map(tuple, np.round(points, 6))))
    if len(pts) < 3:
        return np.array(pts)

    def half(seq):
        h = []
        for p in seq:
            while len(h) >= 2 and cross2(np.subtract(h[-1], h[-2]), np.subtract(p, h[-2])) <= 0:
                h.pop()
            h.append(p)
        return h

    lower, upper = half(pts), half(reversed(pts))
    return np.array(lower[:-1] + upper[:-1])


def ray_radius(poly, centre, direction):
    """Distance from centre along direction to the polygon's boundary."""
    best = 0.0
    n = len(poly)
    for i in range(n):
        a, b = poly[i] - centre, poly[(i + 1) % n] - centre
        e = b - a
        den = direction[0] * e[1] - direction[1] * e[0]
        if abs(den) < 1e-12:
            continue
        t = (a[0] * e[1] - a[1] * e[0]) / den
        s = (a[0] * direction[1] - a[1] * direction[0]) / den
        if t > 0 and -1e-9 <= s <= 1 + 1e-9:
            best = max(best, t)
    return best


def convexify(P, ids, axis_of, ease_of, band=0.012):
    """Pushes each vertex out to the convex hull of its cross-section plus ease.

    axis_of(i) -> (s, centre_2d, uv_2d): position along the part's axis, the
    section centre and the vertex's 2D coordinates in the section plane.
    """
    info = {i: axis_of(i) for i in ids}
    out = {}
    s_all = np.array([info[i][0] for i in ids])
    for i in ids:
        s, centre, q = info[i]
        near = [j for j, sj in zip(ids, s_all) if abs(sj - s) <= band]
        poly = hull(np.array([info[j][2] for j in near]))
        d = q - centre
        r0 = float(np.linalg.norm(d))
        if r0 < 1e-6 or len(poly) < 3:
            out[i] = (s, centre, d, r0)
            continue
        direction = d / r0
        r = max(r0, ray_radius(poly, centre, direction)) + ease_of(i, s)
        out[i] = (s, centre, direction, r)
    return out


def hang(section, ids, from_top=True, slope=0.15, bins=48):
    """Downward running limit on radius per angle bin: cloth hangs from what is
    above it instead of following hollows (slope = allowed inward lean)."""
    by_bin = {}
    for i in ids:
        s, centre, direction, r = section[i]
        ang = np.arctan2(direction[0], direction[1])
        by_bin.setdefault(int((ang + np.pi) / (2 * np.pi) * bins) % bins, []).append(i)
    for members in by_bin.values():
        members.sort(key=lambda i: -section[i][0] if from_top else section[i][0])
        best = None
        for i in members:
            s, centre, direction, r = section[i]
            if best is not None:
                r = max(r, best[1] - slope * abs(best[0] - s))
            if best is None or r > best[1] - slope * abs(best[0] - s):
                best = (s, r)
            section[i] = (s, centre, direction, r)


def flare(section, ids, start, rate, bins=48):
    """Below `start`, radius grows by `rate` per metre of drop (A-line)."""
    by_bin = {}
    for i in ids:
        s, centre, direction, r = section[i]
        ang = np.arctan2(direction[0], direction[1])
        by_bin.setdefault(int((ang + np.pi) / (2 * np.pi) * bins) % bins, []).append(i)
    for members in by_bin.values():
        members.sort(key=lambda i: -section[i][0])
        top_r = None
        for i in members:
            s, centre, direction, r = section[i]
            if s <= start:
                if top_r is None:
                    top_r = (s, r)
                r = max(r, top_r[1] + rate * (top_r[0] - s))
            section[i] = (s, centre, direction, r)


def apply_vertical(section, P, new):
    for i, (s, centre, direction, r) in section.items():
        q = centre + direction * r
        new[i] = (q[0], P[i][1], q[1])


def neighbours_of(tris, n):
    nb = [set() for _ in range(n)]
    for f in quads(tris):
        loop = list(dict.fromkeys(f)) if len(f) == 3 else [f[0], f[1], f[2], f[5]]
        for k in range(len(loop)):
            a, b = loop[k], loop[(k + 1) % len(loop)]
            nb[a].add(b)
            nb[b].add(a)
    return nb


def smooth_displacement(P, shaped, tris, iterations=6):
    ids = sorted(shaped)
    disp = {i: np.array(shaped[i]) - P[i] for i in ids}
    nb = neighbours_of(tris, len(P))
    for _ in range(iterations):
        nxt = {}
        for i in ids:
            ring = [disp[j] for j in nb[i] if j in disp]
            nxt[i] = 0.5 * disp[i] + 0.5 * (sum(ring) / len(ring)) if ring else disp[i]
        disp = nxt
    return {i: P[i] + disp[i] for i in ids}


# --- shaping per template -------------------------------------------------

def torso_axis(P):
    def axis_of(i):
        p = P[i]
        return p[1], np.array([0.0, 0.0]), np.array([p[0], p[2]])
    return axis_of


def arm_axes(P, ids):
    """Per side, the arm's principal axis from its vertices."""
    axes = {}
    for side in (-1, 1):
        pts = np.array([P[i] for i in ids if np.sign(P[i][0]) == side and abs(P[i][0]) > TORSO_X])
        if len(pts) < 10:
            continue
        c = pts.mean(axis=0)
        _, _, vt = np.linalg.svd(pts - c)
        a = vt[0] if vt[0][0] * side > 0 else -vt[0]
        u = np.cross(a, [0, 0, 1.0])
        u /= np.linalg.norm(u)
        w = np.cross(a, u)
        axes[side] = (c, a, u, w)
    return axes


def shape_top(P, ids, ease=0.022, sleeve_ease=0.016, sleeve_open=0.012, hang_slope=0.12):
    torso = [i for i in ids if abs(P[i][0]) <= TORSO_X or P[i][1] > 1.33]
    arms = [i for i in ids if i not in set(torso)]
    new = {}
    section = convexify(P, torso, torso_axis(P), lambda i, s: ease)
    hang(section, torso, slope=hang_slope)
    apply_vertical(section, P, new)
    for side, (c, a, u, w) in arm_axes(P, arms).items():
        mine = [i for i in arms if np.sign(P[i][0]) == side]
        s_vals = {i: float(np.dot(P[i] - c, a)) for i in mine}
        s_max = max(s_vals.values()) if mine else 0

        def axis_of(i, c=c, a=a, u=u, w=w):
            d = P[i] - c
            s = float(np.dot(d, a))
            ring = [P[j] for j in mine if abs(s_vals[j] - s) < 0.012]
            cc = np.mean(ring, axis=0)
            return s, np.array([np.dot(cc - c, u), np.dot(cc - c, w)]), np.array([np.dot(d, u), np.dot(d, w)])

        sec = convexify(P, mine, axis_of, lambda i, s: sleeve_ease + sleeve_open * max(0.0, s / max(s_max, 1e-6)))
        for i, (s, centre, direction, r) in sec.items():
            q2 = centre + direction * r
            new[i] = tuple(c + a * s + u * q2[0] + w * q2[1])
    return new


def shape_trousers(P, ids, ease=0.014, knee=0.50):
    new = {}
    pelvis = [i for i in ids if P[i][1] >= CROTCH]
    legs = [i for i in ids if P[i][1] < CROTCH]
    sec = convexify(P, pelvis, torso_axis(P), lambda i, s: ease)
    apply_vertical(sec, P, new)
    for side in (-1, 1):
        mine = [i for i in legs if np.sign(P[i][0]) == side]
        if not mine:
            continue
        rings = {}
        for i in mine:
            rings.setdefault(round(P[i][1] / 0.012), []).append(i)
        centre_of = {k: np.mean([[P[j][0], P[j][2]] for j in v], axis=0) for k, v in rings.items()}

        def axis_of(i):
            k = round(P[i][1] / 0.012)
            return P[i][1], centre_of[k], np.array([P[i][0], P[i][2]])

        sec = convexify(P, mine, axis_of, lambda i, s: ease)
        # Straight leg: below the knee every ring keeps at least the knee's
        # cross-section, following the leg's own axis (legs slant in an A-pose), so
        # the width carries down to the hem instead of narrowing to the ankle.
        bins = 24

        def bin_of(direction):
            return int((np.arctan2(direction[0], direction[1]) + np.pi) / (2 * np.pi) * bins) % bins

        knee_r = {}
        for i, (s_, centre, direction, r) in sec.items():
            if abs(s_ - knee) < 0.015:
                knee_r[bin_of(direction)] = max(knee_r.get(bin_of(direction), 0.0), r)
        for i, (s_, centre, direction, r) in sec.items():
            if s_ < knee and knee_r:
                b = bin_of(direction)
                ref = knee_r.get(b) or max(knee_r.get((b - 1) % bins, 0.0), knee_r.get((b + 1) % bins, 0.0))
                r = max(r, ref)
            q = centre + direction * r
            new[i] = (q[0], P[i][1], q[1])
    return new


def shape_skirt(P, ids, ease=0.012, hip=0.86, rate=0.30):
    new = {}
    sec = convexify(P, ids, torso_axis(P), lambda i, s: ease)
    flare(sec, ids, hip, rate)
    apply_vertical(sec, P, new)
    return new


def straighten_hems(new, tris, band=0.035, split_x=False, neckline=0.0):
    """Open-edge vertices near the garment's lowest point are snapped to one
    height, so the hem is a straight line instead of following the quad grid's
    steps. With split_x, each side (trouser leg) gets its own hem height."""
    count = {}
    for f in quads(tris):
        loop = list(dict.fromkeys(f)) if len(f) == 3 else [f[0], f[1], f[2], f[5]]
        for k in range(len(loop)):
            e = tuple(sorted((loop[k], loop[(k + 1) % len(loop)])))
            count[e] = count.get(e, 0) + 1
    boundary = {v for e, c in count.items() if c == 1 for v in e if v in new}
    groups = [[v for v in boundary if new[v][0] < 0], [v for v in boundary if new[v][0] >= 0]] if split_x else [list(boundary)]
    for group in groups:
        if not group:
            continue
        low = min(new[v][1] for v in group)
        hem = [v for v in group if new[v][1] <= low + band]
        y = float(np.mean([new[v][1] for v in hem]))
        for v in hem:
            new[v] = (new[v][0], y, new[v][2])
    if neckline > 0:
        # The neckline too: open-edge vertices near the top, centred on the body axis.
        top = [v for v in boundary if abs(new[v][0]) < 0.12]
        if top:
            high = max(new[v][1] for v in top)
            ring = [v for v in top if new[v][1] >= high - neckline]
            y = float(np.mean([new[v][1] for v in ring]))
            for v in ring:
                new[v] = (new[v][0], y, new[v][2])
    return new


def straighten_sleeves(new, tris, axes, band=0.03):
    """Sleeve openings: open-edge vertices near each sleeve's end are moved along
    the arm axis to one axial position, so the opening is a clean ring."""
    count = {}
    for f in quads(tris):
        loop = list(dict.fromkeys(f)) if len(f) == 3 else [f[0], f[1], f[2], f[5]]
        for k in range(len(loop)):
            e = tuple(sorted((loop[k], loop[(k + 1) % len(loop)])))
            count[e] = count.get(e, 0) + 1
    boundary = {v for e, c in count.items() if c == 1 for v in e if v in new}
    for side, (c, a, u, w) in axes.items():
        mine = [v for v in boundary if np.sign(new[v][0]) == side and abs(new[v][0]) > TORSO_X + 0.03]
        if not mine:
            continue
        s = {v: float(np.dot(np.asarray(new[v]) - c, a)) for v in mine}
        far = max(s.values())
        ring = [v for v in mine if s[v] >= far - band]
        target = float(np.mean([s[v] for v in ring]))
        for v in ring:
            new[v] = tuple(np.asarray(new[v]) + (target - s[v]) * a)
    return new


# --- binding ----------------------------------------------------------------

def vertex_normals(P, tris):
    N = np.zeros_like(P)
    T = np.array(tris).reshape(-1, 3)
    fn = np.cross(P[T[:, 1]] - P[T[:, 0]], P[T[:, 2]] - P[T[:, 0]])
    for k in range(3):
        np.add.at(N, T[:, k], fn)
    return N / (np.linalg.norm(N, axis=1, keepdims=True) + 1e-12)


def closest_on_triangle(p, a, b, c):
    """Closest point to p on triangle abc, as barycentric (wa, wb, wc)."""
    ab, ac, ap = b - a, c - a, p - a
    d1, d2 = ab @ ap, ac @ ap
    if d1 <= 0 and d2 <= 0:
        return 1.0, 0.0, 0.0
    bp = p - b
    d3, d4 = ab @ bp, ac @ bp
    if d3 >= 0 and d4 <= d3:
        return 0.0, 1.0, 0.0
    vc = d1 * d4 - d3 * d2
    if vc <= 0 and d1 >= 0 and d3 <= 0:
        v = d1 / (d1 - d3)
        return 1 - v, v, 0.0
    cp = p - c
    d5, d6 = ab @ cp, ac @ cp
    if d6 >= 0 and d5 <= d6:
        return 0.0, 0.0, 1.0
    vb = d5 * d2 - d1 * d6
    if vb <= 0 and d2 >= 0 and d6 <= 0:
        w = d2 / (d2 - d6)
        return 1 - w, 0.0, w
    va = d3 * d6 - d5 * d4
    if va <= 0 and (d4 - d3) >= 0 and (d5 - d6) >= 0:
        w = (d4 - d3) / ((d4 - d3) + (d5 - d6))
        return 0.0, 1 - w, w
    den = 1 / (va + vb + vc)
    v, w = vb * den, vc * den
    return 1 - v - w, v, w


def frame(a, b, n):
    e1 = (b - a) - np.dot(b - a, n) * n
    e1 /= np.linalg.norm(e1) + 1e-12
    return e1, np.cross(n, e1)


def bind(P, body_tris, body_normals, garment_pos, allowed_body):
    """For each garment vertex: nearest allowed body triangle, barycentric
    weights, and the offset (normal, tangent1, tangent2) in its local frame."""
    T = np.array(body_tris).reshape(-1, 3)
    ok = np.array([all(allowed_body[v] for v in t) for t in T])
    tri_ids = np.nonzero(ok)[0]
    cent = P[T[tri_ids]].mean(axis=1)
    out = []
    for g in garment_pos:
        g = np.asarray(g)
        near = tri_ids[np.argsort(np.linalg.norm(cent - g, axis=1))[:24]]
        best = None
        for t in near:
            a, b, c = P[T[t]]
            wa, wb, wc = closest_on_triangle(g, a, b, c)
            q = wa * a + wb * b + wc * c
            dist = np.linalg.norm(g - q)
            if best is None or dist < best[0]:
                best = (dist, t, wb, wc, q)
        _, t, wb, wc, q = best
        i0, i1, i2 = T[t]
        n = (1 - wb - wc) * body_normals[i0] + wb * body_normals[i1] + wc * body_normals[i2]
        n /= np.linalg.norm(n) + 1e-12
        e1, e2 = frame(P[i0], P[i1], n)
        d = g - q
        out.append((int(i0), int(i1), int(i2), float(wb), float(wc), float(d @ n), float(d @ e1), float(d @ e2)))
    return out


def evaluate(binding, P, normals):
    """The runtime formula, for previews and the self-check."""
    out = []
    for i0, i1, i2, wb, wc, dn, t1, t2 in binding:
        wa = 1 - wb - wc
        q = wa * P[i0] + wb * P[i1] + wc * P[i2]
        n = wa * normals[i0] + wb * normals[i1] + wc * normals[i2]
        n /= np.linalg.norm(n) + 1e-12
        e1, e2 = frame(P[i0], P[i1], n)
        out.append(q + dn * n + t1 * e1 + t2 * e2)
    return np.array(out)


# --- panels, UVs and hidden body ---------------------------------------------

def split_panels(new_pos, tris, sleeve_axes=None):
    """Front/back by the face's direction from the garment's own axis; vertices
    on the side seam are duplicated so each panel has its own UVs."""
    faces = quads(tris)
    front_faces, back_faces = [], []
    for f in faces:
        idx = list(dict.fromkeys(f))
        c = np.mean([new_pos[i] for i in idx], axis=0)
        z_ref = 0.0
        if sleeve_axes and abs(c[0]) > TORSO_X and c[1] < 1.36:
            side = 1 if c[0] > 0 else -1
            if side in sleeve_axes:
                ac, a, u, w = sleeve_axes[side]
                z_ref = (ac + a * np.dot(c - ac, a))[2]
        # The photo only goes where the surface faces the camera: beyond ~69° (normal z <
        # 0.35) a front photo would be smeared sideways, so those faces join the
        # unknown region (Gemini's glancing-angle point, verified on the review grid).
        loop = idx if len(idx) == 3 else [f[0], f[1], f[2], f[5]]
        a, b, cc = (np.asarray(new_pos[i]) for i in loop[:3])
        n = np.cross(b - a, cc - a)
        n = n / (np.linalg.norm(n) + 1e-12)
        outward = c - np.array([0.0, c[1], 0.0])
        if np.dot(n, outward) < 0:
            n = -n
        facing = n[2] >= 0.35
        (front_faces if c[2] >= z_ref and facing else back_faces).append(f)
    return front_faces, back_faces


def closest_points(p, a, b, c):
    """Closest points on triangles a/b/c to points p, row by row (Ericson 5.1.5)."""
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
    with np.errstate(divide="ignore", invalid="ignore"):
        for mask, value in (
            ((va <= 0) & (d4 - d3 >= 0) & (d5 - d6 >= 0), b + ((d4 - d3) / ((d4 - d3) + (d5 - d6)))[:, None] * (c - b)),
            ((vb <= 0) & (d2 >= 0) & (d6 <= 0), a + (d2 / (d2 - d6))[:, None] * ac),
            ((d6 >= 0) & (d5 <= d6), c),
            ((vc <= 0) & (d1 >= 0) & (d3 <= 0), a + (d1 / (d1 - d3))[:, None] * ab),
            ((d3 >= 0) & (d4 <= d3), b),
            ((d1 <= 0) & (d2 <= 0), a),
        ):
            out[mask] = value[mask]
    return out


def skin_distance(points, P, T, k=48):
    """Signed distance from each point to the closest skin triangle (negative behind
    its face), with that triangle's unit normal and the closest point."""
    from scipy.spatial import cKDTree

    A, B, C = P[T[:, 0]], P[T[:, 1]], P[T[:, 2]]
    _, cand = cKDTree((A + B + C) / 3).query(points, k=k)
    n, m = cand.shape
    flat = cand.reshape(-1)
    pr = np.repeat(points, m, axis=0)
    q = closest_points(pr, A[flat], B[flat], C[flat])
    d = np.linalg.norm(pr - q, axis=1).reshape(n, m)
    best = d.argmin(axis=1)
    tri = cand[np.arange(n), best]
    qb = q.reshape(n, m, 3)[np.arange(n), best]
    fn = np.cross(B[tri] - A[tri], C[tri] - A[tri])
    fn /= np.linalg.norm(fn, axis=1, keepdims=True) + 1e-12
    sign = np.sign(np.einsum("ij,ij->i", points - qb, fn))
    return sign * d[np.arange(n), best], fn, qb


def clear_of_body(pos, P, body_tris, below=0.003, target=0.007, passes=4):
    """Moves garment vertices closer than `below` to the skin (or inside it) to
    `target` above the closest skin point, along that face's normal. Only the
    armpits need it today; everything else is left exactly where shaping put it."""
    T = np.array(body_tris).reshape(-1, 3)
    keys = list(pos)
    X = np.array([pos[k] for k in keys], dtype=np.float64)
    moved = np.zeros(len(X), bool)
    for _ in range(passes):
        sd, fn, q = skin_distance(X, P, T)
        need = sd < below
        if not need.any():
            break
        X[need] = q[need] + target * fn[need]
        moved |= need
    return {k: X[i] for i, k in enumerate(keys)}, int(moved.sum())


def folds(pos, tris, limit_deg):
    """Vertices of edges whose two faces differ by more than `limit_deg`."""
    T = np.array(tris).reshape(-1, 3)
    fn = {}
    for f, (a, b, c) in enumerate(T):
        n = np.cross(pos[b] - pos[a], pos[c] - pos[a])
        fn[f] = n / (np.linalg.norm(n) + 1e-12)
    edges = {}
    for f, (a, b, c) in enumerate(T):
        for u, v in ((a, b), (b, c), (c, a)):
            edges.setdefault((min(u, v), max(u, v)), []).append(f)
    limit = np.cos(np.radians(limit_deg))
    bad = set()
    for (u, v), fs in edges.items():
        if len(fs) == 2 and fn[fs[0]] @ fn[fs[1]] < limit:
            for f in fs:
                bad.update(int(x) for x in T[f])
    return bad


def unfold_and_clear(pos, tris, P, body_tris, limit_deg=75.0, rounds=30):
    """Alternates skin clearance with Laplacian relaxation of folded creases (and
    their one-ring) until neither is needed. Returns positions and counts."""
    nb = {}
    T = np.array(tris).reshape(-1, 3)
    for a, b, c in T:
        for u, v in ((a, b), (b, c), (c, a)):
            nb.setdefault(int(u), set()).add(int(v))
            nb.setdefault(int(v), set()).add(int(u))
    uses = {}
    for a, b, c in T:
        for u, v in ((a, b), (b, c), (c, a)):
            key = (min(u, v), max(u, v))
            uses[key] = uses.get(key, 0) + 1
    boundary_nb = {}
    for (u, v), k in uses.items():
        if k == 1:
            boundary_nb.setdefault(int(u), set()).add(int(v))
            boundary_nb.setdefault(int(v), set()).add(int(u))
    cleared_total, relaxed = 0, set()
    for _ in range(rounds):
        pos, cleared = clear_of_body(pos, P, body_tris)
        cleared_total += cleared
        bad = folds(pos, tris, limit_deg)
        if not bad:
            break
        region = set(bad)
        for v in bad:
            region |= nb.get(v, set())
        relaxed |= region
        moved = dict(pos)
        for v in region:
            # Open edges (hems, armholes) relax along the edge only, so they stay lines.
            ring = boundary_nb.get(v) or nb.get(v)
            centre = np.mean([pos[u] for u in ring], axis=0)
            moved[v] = pos[v] + 0.5 * (centre - pos[v])
        pos = moved
    pos, cleared = clear_of_body(pos, P, body_tris)
    cleared_total += cleared
    return pos, cleared_total, len(relaxed), len(folds(pos, tris, limit_deg))


def rays_hit(origins, directions, tris, reach):
    """Whether each ray (origin, unit direction) meets any triangle within `reach`
    (Moller-Trumbore, both faces)."""
    a, b, c = tris[:, 0], tris[:, 1], tris[:, 2]
    e1, e2 = b - a, c - a
    hit = np.zeros(len(origins), bool)
    for start in range(0, len(origins), 256):
        o = origins[start:start + 256][:, None, :]
        d = directions[start:start + 256][:, None, :]
        pv = np.cross(d, e2[None])
        det = np.einsum("ijk,jk->ij", pv, e1)
        ok = np.abs(det) > 1e-12
        inv = np.where(ok, 1 / np.where(ok, det, 1), 0)
        tv = o - a[None]
        u = np.einsum("ijk,ijk->ij", tv, pv) * inv
        qv = np.cross(tv, e1[None])
        v = np.einsum("ijk,ijk->ij", np.broadcast_to(d, qv.shape), qv) * inv
        t = np.einsum("ijk,jk->ij", qv, e2) * inv
        found = ok & (u >= 0) & (v >= 0) & (u + v <= 1) & (t > 0) & (t <= reach)
        hit[start:start + 256] = found.any(axis=1)
    return hit


def build_template(name, P, body_tris, body_normals, sel_tris, new, allowed_body, hide_region, sleeve_axes=None):
    used = sorted(set(sel_tris))
    new = {v: new.get(v, tuple(P[v])) for v in used}
    front, back = split_panels(new, sel_tris, sleeve_axes)
    verts, canonical, remap = [], [], {}

    def vid(src, panel):
        key = (src, panel)
        if key not in remap:
            remap[key] = len(verts)
            verts.append((src, panel))
        return remap[key]

    front_idx = [vid(v, 0) for f in front for v in f]
    back_idx = [vid(v, 1) for f in back for v in f]
    first = {}
    for k, (src, _) in enumerate(verts):
        canonical.append(first.setdefault(src, k))

    pos = {v: np.asarray(new.get(v, P[v])) for v in used}
    pos, cleared, relaxed, folded = unfold_and_clear(pos, sel_tris, P, body_tris)
    binding = bind(P, body_tris, body_normals, [pos[src] for src, _ in verts], allowed_body)

    # Front photo projection over the front panel's own bounds; the back uses the
    # same mapping (the renderer decides what an unknown region shows).
    fp = np.array([pos[src] for src, panel in verts if panel == 0]) if front else np.array([[0, 0, 0]])
    x0, x1 = fp[:, 0].min(), fp[:, 0].max()
    y0, y1 = fp[:, 1].min(), fp[:, 1].max()
    uvs = [((pos[s][0] - x0) / max(x1 - x0, 1e-6), (y1 - pos[s][1]) / max(y1 - y0, 1e-6)) for s, _ in verts]
    uvs = [(min(max(u, 0.0), 1.0), min(max(v, 0.0), 1.0)) for u, v in uvs]

    # Hidden body: triangles whose vertices are all covered by the garment: a ray from
    # the skin along its outward normal meets the fabric within 8 cm. Skin above a
    # neckline or beyond a cuff misses the fabric and stays visible; skin under it is
    # hidden right up to the openings. (Fixed region margins of 3-6 cm left skin under
    # the fabric unhidden, and it poked through as jagged teeth along necklines and
    # cuffs; Atelier close-ups.) The region bounds only exclude far-away skin.
    T = np.array(body_tris).reshape(-1, 3)
    G = np.array([[pos[v] for v in f] for f in np.array(sel_tris).reshape(-1, 3)])
    cand = np.array([i for i in range(len(P)) if hide_region(P[i])], dtype=np.int64)
    inside = np.zeros(len(P), bool)
    if len(cand):
        inside[cand] = rays_hit(P[cand], body_normals[cand], G, reach=0.08)
    hidden = [t for t in range(len(T)) if inside[T[t]].all()]
    return {
        "name": name, "verts": verts, "canonical": canonical, "binding": binding, "uvs": uvs,
        "front": front_idx, "back": back_idx, "hidden": hidden,
        "rest": {v: pos[v] for v in used}, "cleared": cleared, "relaxed": relaxed, "folded": folded,
    }


def vertex_normals_of(pos, tris, used):
    index = {v: k for k, v in enumerate(used)}
    Pm = np.array([pos[v] for v in used])
    T = np.array([index[v] for v in tris]).reshape(-1, 3)
    N = np.zeros_like(Pm)
    fn = np.cross(Pm[T[:, 1]] - Pm[T[:, 0]], Pm[T[:, 2]] - Pm[T[:, 0]])
    for k in range(3):
        np.add.at(N, T[:, k], fn)
    N /= np.linalg.norm(N, axis=1, keepdims=True) + 1e-12
    # Orient outward from the body's vertical axis.
    out = np.einsum("ij,ij->i", N, np.c_[Pm[:, 0], np.zeros(len(Pm)), Pm[:, 2]])
    return N if out.sum() >= 0 else -N


def write(templates, out_path):
    blob = bytearray(b"RIGGARM1") + struct.pack("<I", len(templates))
    for t in templates:
        blob += t["name"].encode().ljust(32, b"\0") + struct.pack("<II", VERSION, len(t["verts"]))
        for k in range(len(t["verts"])):
            i0, i1, i2, wb, wc, dn, t1, t2 = t["binding"][k]
            u, v = t["uvs"][k]
            blob += struct.pack("<3I5f2fI", i0, i1, i2, wb, wc, dn, t1, t2, u, v, t["canonical"][k])
        for key in ("front", "back", "hidden"):
            blob += struct.pack("<I", len(t[key])) + struct.pack(f"<{len(t[key])}I", *t[key])
    Path(out_path).write_bytes(bytes(blob))
    return len(blob)


def main():
    asset, out = sys.argv[1], sys.argv[2]
    preview = Path(sys.argv[3]) if len(sys.argv) > 3 else None
    P, subs, _ = pa.read_asset(asset)
    P = P.astype(np.float64)
    body = subs["body"].reshape(-1).tolist()
    tights = subs["tights"].reshape(-1).tolist()
    skirt = subs["skirt"].reshape(-1).tolist()
    body_set = set(body)
    bn = vertex_normals(P, body)

    def is_arm(p):
        return abs(p[0]) > TORSO_X and p[1] > 0.84

    allowed_torso = [i in body_set and not is_arm(P[i]) and P[i][1] > 0.40 for i in range(len(P))]
    allowed_any = [i in body_set for i in range(len(P))]
    allowed_lower = [i in body_set and not is_arm(P[i]) for i in range(len(P))]

    templates = []
    # 1. Relaxed T-shirt: hip-length hem, elbow sleeves.
    tee_tris = select(P, tights, lambda c: 0.84 <= c[1] <= NECK and abs(c[0]) <= 0.31)
    tee_ids = sorted(set(tee_tris))
    tee_new = straighten_hems(smooth_displacement(P, shape_top(P, tee_ids), tee_tris), tee_tris, neckline=0.025)
    axes = arm_axes(P, tee_ids)
    tee_new = straighten_sleeves(tee_new, tee_tris, axes)
    templates.append(build_template(
        "tee", P, body, bn, tee_tris, tee_new, allowed_any,
        lambda p: 0.86 <= p[1] <= NECK + 0.04 and abs(p[0]) <= 0.45, axes))

    # 2. Straight-leg trousers: waist to ankle.
    tr_tris = select(P, tights, lambda c: 0.06 <= c[1] <= WAIST and abs(c[0]) <= 0.33)
    tr_ids = sorted(set(tr_tris))
    tr_new = straighten_hems(smooth_displacement(P, shape_trousers(P, tr_ids), tr_tris), tr_tris, split_x=True)
    templates.append(build_template(
        "trousers", P, body, bn, tr_tris, tr_new, allowed_lower,
        lambda p: 0.04 <= p[1] <= WAIST + 0.03 and abs(p[0]) <= 0.33))

    # 3. A-line skirt: waist to knee.
    sk_tris = select(P, skirt, lambda c: c[1] >= 0.46)
    sk_ids = sorted(set(sk_tris))
    sk_new = straighten_hems(smooth_displacement(P, shape_skirt(P, sk_ids), sk_tris, iterations=3), sk_tris)
    templates.append(build_template(
        "skirt", P, body, bn, sk_tris, sk_new, allowed_torso,
        lambda p: 0.74 <= p[1] <= WAIST + 0.03 and abs(p[0]) <= 0.25))

    # 4. Simple sleeveless dress: bodice from the tights, A-line skirt to below the knee.
    bod_tris = select(P, tights, lambda c: 0.95 <= c[1] <= NECK - 0.03 and abs(c[0]) <= TORSO_X)
    bod_ids = sorted(set(bod_tris))
    bod_new = shape_top(P, bod_ids, ease=0.010, hang_slope=0.25)
    dsk_tris = select(P, skirt, lambda c: c[1] >= 0.40)
    dsk_new = shape_skirt(P, sorted(set(dsk_tris)), ease=0.014, rate=0.22)
    dress_new = straighten_hems(smooth_displacement(P, {**bod_new, **dsk_new}, bod_tris + dsk_tris, iterations=3), bod_tris + dsk_tris, neckline=0.025)
    templates.append(build_template(
        "dress", P, body, bn, bod_tris + dsk_tris, dress_new, allowed_torso,
        lambda p: 0.74 <= p[1] <= NECK + 0.04 and abs(p[0]) <= 0.24))

    size = write(templates, out)
    report = {}
    for t in templates:
        rest = np.array([t["rest"][s] for s, _ in t["verts"]])
        err = np.abs(evaluate(t["binding"], P, bn) - rest).max()
        report[t["name"]] = {"vertices": len(t["verts"]), "front_tris": len(t["front"]) // 3,
                             "back_tris": len(t["back"]) // 3, "hidden_body_tris": len(t["hidden"]),
                             "vertices_cleared_of_skin": t["cleared"],
                             "vertices_relaxed_out_of_folds": t["relaxed"], "folded_vertices_left": t["folded"],
                             "rest_reconstruction_error_m": float(err)}
        if preview:
            preview.mkdir(parents=True, exist_ok=True)
            with open(preview / f"{t['name']}.obj", "w") as f:
                for p in rest:
                    f.write(f"v {p[0]} {p[1]} {p[2]}\n")
                for idx in (t["front"], t["back"]):
                    for k in range(0, len(idx), 3):
                        f.write(f"f {idx[k] + 1} {idx[k + 1] + 1} {idx[k + 2] + 1}\n")
    print(json.dumps({"bytes": size, "templates": report}, indent=1))


if __name__ == "__main__":
    main()
