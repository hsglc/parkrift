"""Python side of tools/park_planner.c: rasterises a level and asks the planner for a way from
each start into its bay with the game's car. Used by tools/design_levels.py."""
import ctypes, math, os, subprocess
import numpy as np
from scipy.ndimage import distance_transform_edt

W, H = 1000, 500
_HERE = os.path.dirname(os.path.abspath(__file__))
_LIB = None


def lib():
    global _LIB
    if _LIB is None:
        out = os.environ.get('PLANNER_SO', '/tmp/park_planner.so')
        if not os.path.exists(out) or os.path.getmtime(out) < os.path.getmtime(os.path.join(_HERE, 'park_planner.c')):
            subprocess.check_call(['cc', '-O2', '-shared', '-fPIC', '-o', out, os.path.join(_HERE, 'park_planner.c'), '-lm'])
        _LIB = ctypes.CDLL(out)
        _LIB.plan.restype = ctypes.c_int
    return _LIB


def raster(obstacles, margin=1.0):
    """obstacles: (kind, x, y, w, h, deg, ...) boxes -> occupancy (1 unit cells) and distance."""
    occ = np.zeros((H, W), dtype=np.uint8)
    ys, xs = np.mgrid[0:H, 0:W]
    px, py = xs + 0.5, ys + 0.5
    for ob in obstacles:
        _, x, y, w, h, d = ob[:6]
        r = math.hypot(w, h) / 2 + margin + 2
        x0, x1 = max(0, int(x - r)), min(W, int(x + r) + 1)
        y0, y1 = max(0, int(y - r)), min(H, int(y + r) + 1)
        if x0 >= x1 or y0 >= y1:
            continue
        a = math.radians(d)
        dx, dy = px[y0:y1, x0:x1] - x, py[y0:y1, x0:x1] - y
        lx = np.abs(dx * math.cos(a) + dy * math.sin(a))
        ly = np.abs(-dx * math.sin(a) + dy * math.cos(a))
        occ[y0:y1, x0:x1] |= ((lx <= w / 2 + margin) & (ly <= h / 2 + margin)).astype(np.uint8)
    if margin > 1:
        m = int(round(margin))
        occ[:m, :] = 1; occ[-m:, :] = 1; occ[:, :m] = 1; occ[:, -m:] = 1
    dist = distance_transform_edt(1 - occ).astype(np.float32)
    # The lot's edges count as walls for the gap too
    edge = np.minimum(np.minimum(px, W - px), np.minimum(py, H - py)).astype(np.float32)
    return occ, np.minimum(dist, edge)


def plan(occ, dist, start, bay, tol, radius=44.0, reverse=False, out_dir=(0.0, 0.0), budget=1_500_000):
    """start (x, y, deg), bay (x, y, length, width, deg) -> dict or None."""
    sx, sy, sd = start
    bx, by, bl, bw, bd = bay
    s = (ctypes.c_double * 3)(sx, sy, math.radians(sd))
    b = (ctypes.c_double * 5)(bx, by, bl, bw, math.radians(bd))
    out = (ctypes.c_double * 6)()
    lib().plan(occ.ctypes.data_as(ctypes.POINTER(ctypes.c_ubyte)), dist.ctypes.data_as(ctypes.POINTER(ctypes.c_float)),
               W, H, s, b, ctypes.c_double(radius), ctypes.c_double(tol), int(reverse),
               ctypes.c_double(out_dir[0]), ctypes.c_double(out_dir[1]), budget, out)
    if out[0] != 1:
        return None
    return dict(length=out[1], switches=int(out[2]), clearance=out[3], expansions=int(out[4]), reverse=out[5])
