#!/usr/bin/env python3
"""Offline preview of the avatar asset or of OBJ files, with no GPU and no Apple toolchain.

    preview_avatar.py asset <file.rigavatar> <out.png> [name=weight ...]
    preview_avatar.py obj <out.png> <a.obj[:rrggbb]> [b.obj[:rrggbb] ...]

Renders a front and a side view with a small numpy z-buffer rasteriser, so a
morph or a garment shell can be checked by eye on Windows or Linux.
Needs numpy and Pillow.
"""
from __future__ import annotations

import struct
import sys

import numpy as np
from PIL import Image


def read_asset(path):
    data = open(path, "rb").read()
    assert data[:8] == b"RIGAVTR1", "bad magic"
    o = 8
    (n,) = struct.unpack_from("<I", data, o); o += 4
    pos = np.frombuffer(data, "<f4", 3 * n, o).reshape(n, 3).copy(); o += 12 * n
    (sm,) = struct.unpack_from("<I", data, o); o += 4
    subs = {}
    for _ in range(sm):
        name = data[o:o + 32].rstrip(b"\0").decode(); o += 32
        (c,) = struct.unpack_from("<I", data, o); o += 4
        subs[name] = np.frombuffer(data, "<u4", c, o).reshape(-1, 3); o += 4 * c
    (tc,) = struct.unpack_from("<I", data, o); o += 4
    targets = {}
    for _ in range(tc):
        name = data[o:o + 32].rstrip(b"\0").decode(); o += 32
        q, c = struct.unpack_from("<fI", data, o); o += 8
        idx = np.frombuffer(data, "<u4", c, o); o += 4 * c
        d = np.frombuffer(data, "<i2", 3 * c, o).reshape(c, 3).astype(np.float32) * q; o += 6 * c
        targets[name] = (idx, d)
    assert o == len(data), "trailing bytes"
    return pos, subs, targets


def read_obj(path):
    v, f = [], []
    for line in open(path):
        if line.startswith("v "):
            v.append([float(x) for x in line.split()[1:4]])
        elif line.startswith("f "):
            idx = [int(t.split("/")[0]) - 1 for t in line.split()[1:]]
            for k in range(1, len(idx) - 1):
                f.append([idx[0], idx[k], idx[k + 1]])
    return np.array(v, np.float32), np.array(f, np.int64)


def render(meshes, size=(360, 720), yaw=0.0):
    """meshes: list of (verts, tris, rgb). Orthographic camera looking down -z."""
    w, h = size
    c, s = np.cos(yaw), np.sin(yaw)
    rot = np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]], np.float32)
    allv = np.concatenate([m[0] for m in meshes])
    top = allv[:, 1].max() * 1.04
    scale = h / top
    img = np.full((h, w, 3), 245, np.float32)
    zbuf = np.full((h, w), -1e9, np.float32)
    light = np.array([0.3, 0.5, 0.8]); light /= np.linalg.norm(light)
    for verts, tris, rgb in meshes:
        p = verts @ rot.T
        sx = p[:, 0] * scale + w / 2
        sy = h - p[:, 1] * scale
        a, b, cc = p[tris[:, 0]], p[tris[:, 1]], p[tris[:, 2]]
        nrm = np.cross(b - a, cc - a)
        nrm /= np.linalg.norm(nrm, axis=1, keepdims=True) + 1e-12
        shade = 0.35 + 0.65 * np.abs(nrm @ light)
        for t in range(len(tris)):
            i0, i1, i2 = tris[t]
            xs = np.array([sx[i0], sx[i1], sx[i2]]); ys = np.array([sy[i0], sy[i1], sy[i2]])
            zs = np.array([p[i0, 2], p[i1, 2], p[i2, 2]])
            x0, x1 = int(max(xs.min(), 0)), int(min(xs.max() + 1, w))
            y0, y1 = int(max(ys.min(), 0)), int(min(ys.max() + 1, h))
            if x0 >= x1 or y0 >= y1:
                continue
            gx, gy = np.meshgrid(np.arange(x0, x1) + 0.5, np.arange(y0, y1) + 0.5)
            den = (ys[1] - ys[2]) * (xs[0] - xs[2]) + (xs[2] - xs[1]) * (ys[0] - ys[2])
            if abs(den) < 1e-9:
                continue
            l0 = ((ys[1] - ys[2]) * (gx - xs[2]) + (xs[2] - xs[1]) * (gy - ys[2])) / den
            l1 = ((ys[2] - ys[0]) * (gx - xs[2]) + (xs[0] - xs[2]) * (gy - ys[2])) / den
            l2 = 1 - l0 - l1
            inside = (l0 >= 0) & (l1 >= 0) & (l2 >= 0)
            z = l0 * zs[0] + l1 * zs[1] + l2 * zs[2]
            zb = zbuf[y0:y1, x0:x1]
            upd = inside & (z > zb)
            zb[upd] = z[upd]
            img[y0:y1, x0:x1][upd] = np.array(rgb, np.float32) * shade[t]
    return img.astype(np.uint8)


def sheet(meshes, out):
    front = render(meshes, yaw=0.0)
    side = render(meshes, yaw=np.pi / 2)
    Image.fromarray(np.concatenate([front, side], axis=1)).save(out)


def main():
    mode = sys.argv[1]
    if mode == "asset":
        pos, subs, targets = read_asset(sys.argv[2])
        out = sys.argv[3]
        for arg in sys.argv[4:]:
            name, wt = arg.split("=")
            idx, d = targets[name]
            pos[idx] += float(wt) * d
        meshes = [(pos, subs["body"].astype(np.int64), (205, 196, 186))]
        sheet(meshes, out)
        print("height", round(float(pos[:, 1].max() - pos[:, 1].min()), 3))
    else:
        out = sys.argv[2]
        meshes = []
        for spec in sys.argv[3:]:
            path, _, col = spec.partition(":")
            col = col or "cdc4ba"
            v, f = read_obj(path)
            meshes.append((v, f, tuple(int(col[i:i + 2], 16) for i in (0, 2, 4))))
        sheet(meshes, out)


if __name__ == "__main__":
    main()
