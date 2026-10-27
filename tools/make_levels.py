"""Generates parking levels 11-50 (Hop/LevelsMore.swift) from six layouts with a rising
difficulty, and checks each one before writing it:
  - both bays fit the car with room to spare and touch nothing,
  - both starts are free,
  - a car-sized disc can drive from each start to its bay (grid search over the free space).

World: 1000 x 500 units (1 unit = 10 cm), y up, angles in degrees, car 44 x 22.
Usage: python3 make_levels.py <Hop/LevelsMore.swift>
"""
import sys, math, random

W, H = 1000, 500
CAR = (44, 22)

NAMES = [  # TR, EN, ES
    ("AVM Otoparkı", "Mall Lot", "Parking del centro comercial"),
    ("Kaldırım Kenarı", "Curbside", "Junto a la acera"),
    ("Çapraz Sıra", "Slanted Row", "Fila inclinada"),
    ("Orta Şerit", "Middle Lane", "Carril central"),
    ("Dolambaç", "Switchback", "Zigzag"),
    ("Kolonlu Kat", "Pillar Deck", "Planta de columnas"),
    ("Ofis Otoparkı", "Office Lot", "Parking de oficinas"),
    ("Sahil Yolu", "Seaside Road", "Paseo marítimo"),
    ("Balık Kılçığı", "Herringbone", "Espiga"),
    ("Sıkışık Sıra", "Packed Row", "Fila llena"),
    ("Koni Koridoru", "Cone Corridor", "Pasillo de conos"),
    ("Yeraltı", "Underground", "Subterráneo"),
    ("Stadyum", "Stadium", "Estadio"),
    ("Eski Şehir", "Old Town", "Casco antiguo"),
    ("Eğik Kat", "Angled Deck", "Planta inclinada"),
    ("Geri Manevra", "Back It In", "Marcha atrás"),
    ("Labirent II", "Maze II", "Laberinto II"),
    ("Kule Otoparkı", "Tower Garage", "Garaje de la torre"),
    ("Hastane", "Hospital", "Hospital"),
    ("Tren Garı", "Station", "Estación"),
    ("Pazar Yeri", "Market Square", "Plaza del mercado"),
    ("Havalimanı", "Airport", "Aeropuerto"),
    ("Kıl Payı", "Hairline", "Por un pelo"),
    ("İkili Sıra", "Double Row", "Doble fila"),
    ("Sinema", "Cinema", "Cine"),
    ("Liman", "Harbor", "Puerto"),
    ("Kampüs", "Campus", "Campus"),
    ("Gece Vardiyası", "Night Shift", "Turno de noche"),
    ("Dar Sokak", "Narrow Street", "Calle estrecha"),
    ("Otel Önü", "Hotel Drop", "Entrada del hotel"),
    ("Kavşak", "Junction", "Cruce"),
    ("Servis Yolu", "Service Road", "Vía de servicio"),
    ("Depo", "Warehouse", "Almacén"),
    ("Fuar Alanı", "Fairground", "Recinto ferial"),
    ("Sıfır Hata", "Zero Margin", "Margen cero"),
    ("Spiral", "Spiral", "Espiral"),
    ("Konser", "Concert Night", "Noche de concierto"),
    ("Şampiyon", "Champion", "Campeón"),
    ("Usta İşi", "Pro Move", "Maniobra pro"),
    ("Final: Kule", "Final: Tower", "Final: La torre"),
]


# ------------------------------------------------------------------ geometry

def corners(cx, cy, w, h, deg):
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    out = []
    for dx, dy in [(-w / 2, -h / 2), (w / 2, -h / 2), (w / 2, h / 2), (-w / 2, h / 2)]:
        out.append((cx + dx * c - dy * s, cy + dx * s + dy * c))
    return out


def overlap(a, b):
    """Separating-axis test for two convex quads."""
    for poly in (a, b):
        for i in range(4):
            x1, y1 = poly[i]
            x2, y2 = poly[(i + 1) % 4]
            nx, ny = y1 - y2, x2 - x1
            pa = [nx * x + ny * y for x, y in a]
            pb = [nx * x + ny * y for x, y in b]
            if max(pa) < min(pb) or max(pb) < min(pa):
                return False
    return True


class Level:
    def __init__(self, name):
        self.name = name
        self.starts, self.spots, self.obs = [], [], []

    def box(self, kind, x, y, w, h, deg=0, tint=0):
        self.obs.append((kind, x, y, w, h, deg, tint))

    def car(self, x, y, deg=0, tint=1):
        self.box('car', x, y, CAR[0], CAR[1], deg, tint)

    def cone(self, x, y):
        self.box('cone', x, y, 14, 14)

    def wall(self, x, y, w, h):
        self.box('wall', x, y, w, h)

    def quads(self):
        return [corners(x, y, w, h, d) for _, x, y, w, h, d, _ in self.obs]

    def check(self):
        quads = self.quads()
        for sx, sy, sw, sh, sd in self.spots:
            if sw < CAR[0] + 14 or sh < CAR[1] + 8:
                return 'spot too small'
            q = corners(sx, sy, sw, sh, sd)
            if any(not (4 <= x <= W - 4 and 4 <= y <= H - 4) for x, y in q):
                return 'spot outside'
            if any(overlap(q, o) for o in quads):
                return 'spot blocked'
        for i in range(len(self.spots)):
            for j in range(i + 1, len(self.spots)):
                a, b = self.spots[i], self.spots[j]
                if overlap(corners(*a), corners(*b)):
                    return 'spots overlap'
        for sx, sy, sd in self.starts:
            q = corners(sx, sy, CAR[0] + 6, CAR[1] + 6, sd)
            if any(overlap(q, o) for o in quads):
                return 'start blocked'
        # Reachability for a disc a little smaller than the car's width
        cell = 6
        gw, gh = W // cell, H // cell
        radius = 13
        free = [[True] * gh for _ in range(gw)]
        for kind, x, y, w, h, d, _ in self.obs:
            r = math.hypot(w, h) / 2 + radius
            for gx in range(max(0, int((x - r) / cell)), min(gw, int((x + r) / cell) + 1)):
                for gy in range(max(0, int((y - r) / cell)), min(gh, int((y + r) / cell) + 1)):
                    px, py = gx * cell + cell / 2, gy * cell + cell / 2
                    a = math.radians(d)
                    lx = (px - x) * math.cos(a) + (py - y) * math.sin(a)
                    ly = -(px - x) * math.sin(a) + (py - y) * math.cos(a)
                    ex = max(0, abs(lx) - w / 2)
                    ey = max(0, abs(ly) - h / 2)
                    if math.hypot(ex, ey) < radius:
                        free[gx][gy] = False
        for gx in range(gw):
            for gy in range(gh):
                px, py = gx * cell, gy * cell
                if px < radius or py < radius or px > W - radius or py > H - radius:
                    free[gx][gy] = False
        for (sx, sy, _), (tx, ty, _, _, _) in zip(self.starts, self.spots):
            start = (int(sx / cell), int(sy / cell))
            goal = (int(tx / cell), int(ty / cell))
            if not free[start[0]][start[1]] or not free[goal[0]][goal[1]]:
                return 'start/goal cell not free'
            seen = {start}
            stack = [start]
            while stack:
                cx, cy = stack.pop()
                if (cx, cy) == goal:
                    break
                for nx, ny in ((cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)):
                    if 0 <= nx < gw and 0 <= ny < gh and free[nx][ny] and (nx, ny) not in seen:
                        seen.add((nx, ny))
                        stack.append((nx, ny))
            if goal not in seen:
                return 'no path'
        return None


# ------------------------------------------------------------------ layouts

def scatter_cones(lv, rng, count, x0, x1, y0, y1):
    for _ in range(count):
        lv.cone(rng.uniform(x0, x1), rng.uniform(y0, y1))


def row_bays(lv, rng, d):
    """Perpendicular bays in a row along the top or bottom, neighbours parked."""
    top = rng.random() < 0.5
    y = 430 if top else 70
    angle = 90
    pitch = 60 - 6 * d
    width = 44 - 6 * d
    xs = [260 + i * pitch for i in range(int((900 - 260) / pitch))]
    free_idx = sorted(rng.sample(range(2, len(xs) - 2), 2))
    if free_idx[1] - free_idx[0] < 2:
        free_idx[1] = min(len(xs) - 2, free_idx[0] + 3)
    for i, x in enumerate(xs):
        if i in free_idx:
            continue
        if rng.random() < 0.85 + 0.15 * d:
            lv.car(x, y + (-2 if top else 2), angle, rng.randint(1, 5))
    lv.spots = [(xs[i], y, 72 - 6 * d, width, angle) for i in free_idx]
    lv.starts = [(100, 250 + (60 if not top else -60), 0), (100, 250 + (120 if not top else -120), 0)]
    scatter_cones(lv, rng, int(2 + 6 * d), 300, 900, 200, 300)
    # A second parked row across the lane when harder
    if d > 0.4:
        y2 = 250
        for x in range(320, 900, int(56)):
            if rng.random() < 0.55:
                lv.car(x, y2 + (40 if not top else -40), 90, rng.randint(1, 5))


def parallel(lv, rng, d):
    """Parallel bays along a curb wall; a second line of cars across the street."""
    bottom = rng.random() < 0.6
    curb = 15 if bottom else H - 15
    y = 52 if bottom else H - 52
    lv.wall(500, curb, 1000, 30)
    gap = 76 - 14 * d
    x = 120
    spots = []
    while x < 940:
        if len(spots) < 2 and x > 220 + 330 * len(spots) and rng.random() < 0.55:
            spots.append(x + 3 + gap / 2)
            x += gap + 6
        else:
            lv.car(x + 22, y, 0, rng.randint(1, 5))
            x += 44 + rng.uniform(10, 26)
    if len(spots) < 2:
        spots = [-500, -500]   # rejected by the check; another seed is tried
    lv.spots = [(sx, y, gap, 32, 0) for sx in sorted(spots)]
    other = H - 52 if bottom else 52
    for xx in range(150, 950, 150 - int(40 * d)):
        lv.car(xx, other, 0, rng.randint(1, 5))
    mid = 250
    lv.starts = [(80, mid - 40, 0), (80, mid + 40, 0)]
    scatter_cones(lv, rng, int(1 + 5 * d), 300, 880, mid - 60, mid + 60)


def angled(lv, rng, d):
    """Angled bays (45-60 degrees) in a row."""
    angle = 45 + 15 * d
    top = rng.random() < 0.5
    y = 400 if top else 100
    deg = angle if not top else -angle
    pitch = 120 - 20 * d
    xs = [280 + i * pitch for i in range(int((900 - 280) / pitch) + 1)]
    free_idx = sorted(rng.sample(range(1, len(xs) - 1), 2))
    for i, x in enumerate(xs):
        if i not in free_idx:
            lv.car(x, y, deg, rng.randint(1, 5))
    lv.spots = [(xs[i], y, 78 - 8 * d, 42 - 4 * d, deg) for i in free_idx]
    lv.starts = [(100, 250 + (-40 if top else 40), 0), (100, 250 + (-110 if top else 110), 0)]
    scatter_cones(lv, rng, int(2 + 5 * d), 300, 880, 220, 280)


def middle_slot(lv, rng, d):
    """A slot in a middle row of cars, reached around the row's end."""
    y = 250
    pitch = 56 + int(10 * (1 - d))
    xs = list(range(240, 900, pitch))
    free_idx = sorted(rng.sample(range(1, len(xs) - 1), 2))
    for i, x in enumerate(xs):
        if i not in free_idx:
            lv.car(x, y, 0, rng.randint(1, 5))
    lv.spots = [(xs[i], y, min(72 - 10 * d, 2 * pitch - 44 - 6), 40 - 6 * d, 0) for i in free_idx]
    lv.starts = [(100, 420, 0), (100, 80, 0)]
    for x in range(200, 900, 140):
        if rng.random() < 0.3 + 0.4 * d:
            lv.car(x, 460, 0, rng.randint(1, 5))
        if rng.random() < 0.3 + 0.4 * d:
            lv.car(x + 60, 40, 0, rng.randint(1, 5))
    scatter_cones(lv, rng, int(1 + 4 * d), 300, 880, 330, 400)


def maze(lv, rng, d):
    """Walls with alternating gaps; the bays at the far end."""
    walls = 2 + int(2 * d)
    xs = [220 + i * (560 / walls) for i in range(walls)]
    for i, x in enumerate(xs):
        gap = 150 - 50 * d
        if i % 2 == 0:
            lv.wall(x, (H - gap) / 2, 20, H - gap)
        else:
            lv.wall(x, H - (H - gap) / 2, 20, H - gap)
    lv.spots = [(890, 140, 76 - 8 * d, 44 - 4 * d, 90), (890, 360, 76 - 8 * d, 44 - 4 * d, 90)]
    lv.car(890, 250, 90, 2)
    lv.car(890, 30, 90, 3) if d > 0.5 else None
    lv.starts = [(90, 120, 0), (90, 380, 0)]
    scatter_cones(lv, rng, int(2 + 4 * d), 260, 820, 60, 440)


def pillars(lv, rng, d):
    """A garage deck: pillars in a grid and angled bays between them."""
    for x in range(300, 900, 160):
        for y in (150, 350):
            lv.wall(x + rng.uniform(-10, 10), y, 24, 24)
    deg = 60 + 20 * d
    lv.spots = [(560, 455, 70 - 6 * d, 38 - 4 * d, 90), (820, 455, 70 - 6 * d, 38 - 4 * d, 90)]
    for x in (480, 640, 740, 900):
        lv.car(x, 458, 90, rng.randint(1, 5))
    for x in (420, 700):
        lv.car(x, 45, deg, rng.randint(1, 5))
    lv.starts = [(90, 250, 0), (90, 80, 0)]
    scatter_cones(lv, rng, int(2 + 6 * d), 260, 880, 200, 300)


LAYOUTS = [row_bays, parallel, angled, middle_slot, maze, pillars]


def build(index):
    d = index / 39
    for attempt in range(400):
        rng = random.Random(index * 7919 + attempt)
        lv = Level(NAMES[index])
        LAYOUTS[index % len(LAYOUTS)](lv, rng, min(1.0, d))
        problem = lv.check()
        if problem is None:
            return lv, attempt
    raise SystemExit(f'level {index + 11}: could not build ({problem})')


def swift(lv):
    tr, en, es = lv.name
    starts = ', '.join(f'start({x:.0f}, {y:.0f}, {d:.0f})' for x, y, d in lv.starts)
    spots = ', '.join(f'spot({x:.0f}, {y:.0f}, {w:.0f}, {h:.0f}, {d:.0f})' for x, y, w, h, d in lv.spots)
    obs = []
    for kind, x, y, w, h, d, tint in lv.obs:
        if kind == 'car':
            obs.append(f'car({x:.0f}, {y:.0f}, {d:.0f}, {tint})')
        elif kind == 'cone':
            obs.append(f'cone({x:.0f}, {y:.0f})')
        else:
            obs.append(f'wall({x:.0f}, {y:.0f}, {w:.0f}, {h:.0f})')
    lines = ',\n                             '.join(', '.join(obs[i:i + 4]) for i in range(0, len(obs), 4))
    return (f'        LevelDef(nameTR: "{tr}", nameEN: "{en}",\n'
            f'                 starts: [{starts}],\n'
            f'                 spots: [{spots}],\n'
            f'                 obstacles: [{lines}])')


def main():
    levels = []
    for i in range(40):
        lv, attempts = build(i)
        levels.append(lv)
        print(f'level {i + 11:2d} {LAYOUTS[i % len(LAYOUTS)].__name__:12s} {lv.name[1]:16s} '
              f'obstacles {len(lv.obs):2d} tries {attempts + 1}')
    body = ',\n\n'.join(swift(lv) for lv in levels)
    spanish = '\n'.join(f'        "{en}": "{es}",' for tr, en, es in NAMES)
    out = f'''import CoreGraphics

// Generated by tools/make_levels.py: parking levels 11-50 (each checked for a free path from
// both starts to both bays). Do not edit by hand; change the script and run it again.

extension Levels {{
    static let moreSpanishNames: [String: String] = [
{spanish}
    ]

    static let more: [LevelDef] = [
{body}
    ]
}}
'''
    open(sys.argv[1], 'w').write(out)


if __name__ == '__main__':
    main()
