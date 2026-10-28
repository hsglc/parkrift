"""Generates parking levels 11-50 (Hop/LevelsMore.swift) from six layouts with a rising
difficulty (bays get tighter, more cars and cones, more maze walls; the time and crash limits,
reverse parking, wet ground and patrol cars come from Hop/Challenge.swift), and checks each one before writing it:
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

    def check(self, radius=13):
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
    width = 44 - 10 * d
    xs = [260 + i * pitch for i in range(int((900 - 260) / pitch))]
    free_idx = sorted(rng.sample(range(2, len(xs) - 2), 2))
    if free_idx[1] - free_idx[0] < 2:
        free_idx[1] = min(len(xs) - 2, free_idx[0] + 3)
    for i, x in enumerate(xs):
        if i in free_idx:
            continue
        if rng.random() < 0.85 + 0.15 * d:
            lv.car(x, y + (-2 if top else 2), angle, rng.randint(1, 5))
    lv.spots = [(xs[i], y, 72 - 10 * d, width, angle) for i in free_idx]
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
    gap = 76 - 17 * d
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
    lv.spots = [(xs[i], y, 78 - 12 * d, 42 - 8 * d, deg) for i in free_idx]
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
    lv.spots = [(xs[i], y, min(72 - 12 * d, 2 * pitch - 44 - 6), 40 - 8 * d, 0) for i in free_idx]
    lv.starts = [(100, 420, 0), (100, 80, 0)]
    for x in range(200, 900, 140):
        if rng.random() < 0.3 + 0.4 * d:
            lv.car(x, 460, 0, rng.randint(1, 5))
        if rng.random() < 0.3 + 0.4 * d:
            lv.car(x + 60, 40, 0, rng.randint(1, 5))
    scatter_cones(lv, rng, int(1 + 4 * d), 300, 880, 330, 400)


def maze(lv, rng, d):
    """Walls with alternating gaps; the bays at the far end."""
    walls = 2 + int(3 * d)
    xs = [220 + i * (560 / walls) for i in range(walls)]
    for i, x in enumerate(xs):
        gap = 150 - 50 * d
        if i % 2 == 0:
            lv.wall(x, (H - gap) / 2, 20, H - gap)
        else:
            lv.wall(x, H - (H - gap) / 2, 20, H - gap)
    lv.spots = [(890, 140, 76 - 14 * d, 44 - 10 * d, 90), (890, 360, 76 - 14 * d, 44 - 10 * d, 90)]
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
    lv.spots = [(560, 455, 70 - 10 * d, 38 - 6 * d, 90), (820, 455, 70 - 10 * d, 38 - 6 * d, 90)]
    for x in (480, 640, 740, 900):
        lv.car(x, 458, 90, rng.randint(1, 5))
    for x in (420, 700):
        lv.car(x, 45, deg, rng.randint(1, 5))
    lv.starts = [(90, 250, 0), (90, 80, 0)]
    scatter_cones(lv, rng, int(2 + 6 * d), 260, 880, 200, 300)


def alcoves(lv, rng, d):
    """Garage alcoves along one side: three walls round each bay, so the car has to be lined up
    in the lane first and go straight in (or back in); the other alcoves hold parked cars and a
    row of cars narrows the lane."""
    top = rng.random() < 0.5
    inner = 46 - 8 * d          # alcove width (car 22)
    depth = 76 - 8 * d          # alcove length (car 44)
    t = 10
    pitch = inner + t
    count = int((900 - 300) / pitch)
    xs = [300 + i * pitch for i in range(count)]
    mouth = 300 if top else 200
    yc = mouth + depth / 2 if top else mouth - depth / 2
    for i in range(count + 1):
        lv.wall(300 - pitch / 2 + i * pitch, yc, t, depth)
    back = yc + (depth / 2 + 5) * (1 if top else -1)
    lv.wall(300 - pitch / 2 + count * pitch / 2, back, count * pitch + t, 10)
    free = sorted(rng.sample(range(1, count - 1), 2))
    if free[1] - free[0] < 3:
        free = [free[0], min(count - 2, free[0] + 3)]
    for i, x in enumerate(xs):
        if i not in free:
            lv.car(x, yc, 90, rng.randint(1, 5))
    lv.spots = [(xs[i], yc, depth - 8, inner - 6, 90) for i in free]
    lane = 150 - 35 * d
    other = mouth - lane if top else mouth + lane
    for x in range(330, 900, 58):
        if rng.random() < 0.5 + 0.4 * d:
            lv.car(x, other + (-11 if top else 11), 0, rng.randint(1, 5))
    lv.starts = [(90, mouth - lane / 2 if top else mouth + lane / 2, 0),
                 (90, (mouth - lane - 60) if top else (mouth + lane + 60), 0)]
    scatter_cones(lv, rng, int(1 + 3 * d), 250, 880, 20, 480)


def turnaround(lv, rng, d):
    """The car starts nose to a dead end: the bays are behind it, past a split row of parked cars
    and cones, so every run begins with a turn in a tight space."""
    lv.wall(985, 250, 30, 500)
    lv.wall(15, 250, 30, 500)
    for x in range(560, 960, 50):
        lv.car(x, 250, 0, rng.randint(1, 5))
    depth = 74 - 10 * d
    width = 42 - 8 * d
    spots = []
    for half, yc in ((0, 125), (1, 375)):
        sy = yc + rng.uniform(-50, 50)
        spots.append((30 + depth / 2 + 4, sy, depth, width, 0))
        for k in (-1, 1):
            lv.car(30 + 26, sy + k * (width + 4), 0, rng.randint(1, 5))
    lv.spots = spots
    lv.starts = [(880, 125 + rng.uniform(-30, 30), 0), (880, 375 + rng.uniform(-30, 30), 0)]
    # Narrow passes between the halves of the lot
    for x in (330 + rng.uniform(-30, 30), 460 + rng.uniform(-30, 30)):
        lv.wall(x, 250, 20, 70 + 90 * d)
    scatter_cones(lv, rng, int(3 + 7 * d), 180, 780, 30, 470)


def island(lv, rng, d):
    """Two bays at an odd angle in an island of parked cars in the middle of the lot, with
    pillars around: the line in has to be planned from far away."""
    ang = rng.choice([30, 60, 120, 150])
    a = math.radians(ang)
    across = (-math.sin(a), math.cos(a))
    cx, cy = rng.uniform(500, 640), 250
    pitch = 42 - 6 * d
    length = 68 - 8 * d
    spots = []
    for k in range(-3, 4):
        x, y = cx + across[0] * k * pitch, cy + across[1] * k * pitch
        if k in (-1, 1):
            spots.append((x, y, length, pitch - 6, ang))
        else:
            lv.car(x, y, ang, rng.randint(1, 5))
    lv.spots = spots
    for i in range(int(4 + 4 * d)):
        t = rng.uniform(0, 2 * math.pi)
        r = rng.uniform(190, 230)
        lv.wall(cx + math.cos(t) * r * 1.3, cy + math.sin(t) * r * 0.9, 26, 26)
    lv.starts = [(90, 110, 0), (90, 390, 0)]
    scatter_cones(lv, rng, int(2 + 6 * d), 200, 900, 20, 480)


def corridor(lv, rng, d):
    """Two walled lanes with a chicane each, ending in a small yard where the bay lies across
    the lane's end between parked cars: a late, tight turn in."""
    width = 112 - 30 * d
    lv.wall(500, 250, 1000, 16)
    for yc in (125, 375):
        for side in (-1, 1):
            edge = yc + side * (width / 2 + 6)
            if abs(edge - 250) > 20 and 15 < edge < 485:
                lv.wall(470, edge, 520, 12)
        # Chicane blocks from alternating sides
        for j, x in enumerate((360, 520)):
            side = 1 if (j + (yc > 250)) % 2 == 0 else -1
            bite = width * (0.32 + 0.12 * d)
            lv.wall(x + rng.uniform(-20, 20), yc + side * (width / 2 - bite / 2), 18, bite)
    depth = 72 - 10 * d
    w = 42 - 8 * d
    spots = []
    for yc in (125, 375):
        sy = yc + rng.uniform(-40, 40)
        spots.append((935, sy, depth, w, 0))
        for k in (-1, 1):
            if 30 < sy + k * (w + 4) < 470:
                lv.car(935, sy + k * (w + 4), 0, rng.randint(1, 5))
    lv.wall(985, 250, 30, 500)
    lv.spots = spots
    lv.starts = [(90, 125, 0), (90, 375, 0)]
    scatter_cones(lv, rng, int(1 + 3 * d), 780, 880, 40, 460)


def slalom(lv, rng, d):
    """A cone slalom down the lot, then a tight parallel bay against the curb."""
    parallel(lv, rng, d)
    gate = 110 - 35 * d
    for j, x in enumerate(range(280, 760, 120)):
        centre = 250 + (60 if j % 2 == 0 else -60) * (1 if rng.random() < 0.5 else 1)
        for y in range(120, 390, 16):
            if abs(y - centre) > gate / 2:
                lv.cone(x, y)


def clutter(lv, rng, d, cars, cones, radius=17):
    """More parked cars and cones round the bays and along the way, so the last metres are a
    squeeze. Each one is kept only if the level still checks out with a wider car disc than
    usual (gaps stay drivable for a 4.4 m car, not just passable for a point), and none lands
    in a bay's entry box."""
    keep_out = []
    for sx, sy, sw, sh, sd in lv.spots:
        keep_out.append(corners(sx, sy, sw + 70, sh + 16, sd))
    for x, y, deg in lv.starts:
        keep_out.append(corners(x, y, 110, 60, deg))

    def try_add(kind, x, y, deg):
        if not (30 < x < W - 30 and 30 < y < H - 30):
            return False
        w, h = (CAR if kind == 'car' else (14, 14))
        q = corners(x, y, w + 6, h + 6, deg)
        if any(overlap(q, k) for k in keep_out):
            return False
        # Never inside or touching another obstacle (cars pushed into each other looked wrong)
        if any(overlap(q, o) for o in lv.quads()):
            return False
        lv.obs.append((kind, x, y, w, h, deg, rng.randint(1, 5) if kind == 'car' else 0))
        if lv.check(radius=radius) is None:
            return True
        lv.obs.pop()
        return False

    placed_cars = placed_cones = 0
    for _ in range(cars * 12):
        if placed_cars >= cars:
            break
        sx, sy, sw, sh, sd = rng.choice(lv.spots)
        r = rng.uniform(70, 190)
        t = rng.uniform(0, 2 * math.pi)
        deg = rng.choice([0, 90, sd, sd + 90, rng.uniform(0, 180)])
        if try_add('car', sx + math.cos(t) * r, sy + math.sin(t) * r, deg):
            placed_cars += 1
    for _ in range(cones * 10):
        if placed_cones >= cones:
            break
        if rng.random() < 0.6:
            sx, sy, *_ = rng.choice(lv.spots)
            x, y = sx + rng.uniform(-150, 150), sy + rng.uniform(-120, 120)
        else:
            x, y = rng.uniform(150, 850), rng.uniform(40, 460)
        if try_add('cone', x, y, 0):
            placed_cones += 1
    return placed_cars, placed_cones


def mirror(lv, horizontal, vertical):
    """Mirrors a finished layout so starts, bays and turns differ between levels."""
    def mx(x):
        return W - x if horizontal else x

    def my(y):
        return H - y if vertical else y

    def ang(deg):
        if horizontal:
            deg = 180 - deg
        if vertical:
            deg = -deg
        # (-180, 180]: the game treats ±90 as a straight bay
        deg = (deg + 180) % 360 - 180
        return 180 if deg == -180 else deg

    # Walls and cones are axis-aligned boxes: only their position moves
    lv.obs = [(k, mx(x), my(y), w, h, ang(dg) if k == 'car' else dg, t) for k, x, y, w, h, dg, t in lv.obs]
    lv.spots = [(mx(x), my(y), w, h, ang(dg)) for x, y, w, h, dg in lv.spots]
    lv.starts = [(mx(x), my(y), ang(dg)) for x, y, dg in lv.starts]


# Easier shapes come first; the new tight ones (alcoves, turnaround, island, corridor, slalom)
# take over as the levels go on
EARLY = [row_bays, parallel, angled, middle_slot, alcoves, island, maze, pillars]
LATE = [alcoves, turnaround, island, corridor, slalom, maze, parallel, angled, row_bays, pillars, middle_slot]
LAYOUTS = EARLY


def layout_for(index):
    pool = EARLY if index < 12 else LATE
    return pool[index % len(pool)]


def build(index):
    # One step harder from the start: tighter bays and more traffic earlier
    d = min(1.0, (index + 5) / 39)
    layout = layout_for(index)
    for attempt in range(600):
        rng = random.Random(index * 7919 + attempt)
        lv = Level(NAMES[index])
        layout(lv, rng, min(1.0, d))
        # Every other level is mirrored left-right, every third top-bottom
        mirror(lv, horizontal=index % 2 == 1, vertical=index % 3 == 2)
        problem = lv.check()
        if problem is None:
            clutter(lv, rng, d, cars=int(3 + 6 * d), cones=int(4 + 8 * d))
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
        print(f'level {i + 11:2d} {layout_for(i).__name__:12s} {lv.name[1]:16s} '
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
