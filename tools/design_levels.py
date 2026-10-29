"""Designs the 50 parking levels (Hop/LevelsMore.swift) on a difficulty curve, from a wide open
first bay to a near-perfect manoeuvre in a packed garage.

How a level is made:
  1. The level's place on the curve (D, 0 = easiest, 1 = hardest) sets its geometry: bay size
     (7.2 x 4.0 m at the start, 5.4 x 2.8 m at the end for a 4.4 x 2.2 m car), aisle width,
     how close the neighbours stand, how many walls, pillars, cars and cones are in the way.
  2. One of thirteen layouts builds slot 0's half of the lot (bays in a row, parallel at a curb,
     garage boxes, a maze, an island at an odd angle, a dead end to turn round in, ...). Slot 1's
     half is its mirror image, so an online race is fair to the metre.
  3. A hybrid A* planner (tools/park_planner.c) drives the game's real car (44 x 22, turning
     radius 4.4 m, forward and reverse, the level's alignment tolerance and back-in rule) from the
     start into the bay. A level it cannot solve is never used. The plan also measures how hard
     the level really is:
       - room for error: the widest safety margin round the car with which it still gets in,
       - manoeuvres: how many times it has to change between drive and reverse,
       - the way: how long it is,
     and with the bay's slack these give a difficulty score.
  4. Several candidates (seeds and geometry nudges) are made for each level and the one whose
     score is closest to the curve is kept, so the levels get harder one by one, by measurement.

The curve rises steadily over five chapters of ten; each chapter's last level is a small boss
(a notch above the curve) and introduces nothing new, the chapter after it brings new layouts.
World: 1000 x 500 units (1 unit = 10 cm), y up, angles in degrees.
Usage: python3 design_levels.py <Hop/LevelsMore.swift> [first last]
"""
import sys, math, random, os, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import level_planner as planner

W, H = 1000, 500
CAR = (44, 22)


# ------------------------------------------------------------------ geometry helpers

def corners(cx, cy, w, h, deg):
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    return [(cx + dx * c - dy * s, cy + dx * s + dy * c)
            for dx, dy in [(-w / 2, -h / 2), (w / 2, -h / 2), (w / 2, h / 2), (-w / 2, h / 2)]]


def overlap(a, b):
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
    """Slot 0's half; `mirror` makes the whole level."""

    def __init__(self, axis):
        self.axis = axis            # 'y': slot 1 is the top/bottom mirror, 'x': left/right
        self.start = None           # (x, y, deg)
        self.spot = None            # (x, y, length, width, deg)
        self.obs = []               # (kind, x, y, w, h, deg, tint)
        self.shared = []            # obstacles on the mirror line (not mirrored)

    def box(self, kind, x, y, w, h, deg=0, tint=0):
        self.obs.append((kind, x, y, w, h, deg, tint))

    def car(self, x, y, deg, rng):
        self.box('car', x, y, CAR[0], CAR[1], deg + rng.uniform(-2.5, 2.5), rng.randint(1, 5))

    def cone(self, x, y):
        self.box('cone', x, y, 14, 14)

    def wall(self, x, y, w, h):
        self.box('wall', x, y, w, h)

    def inside_half(self, x, y, pad=0):
        if self.axis == 'y':
            return 250 + pad <= y <= H - pad and pad <= x <= W - pad
        return pad <= x <= 500 - pad and pad <= y <= H - pad

    def free(self, quad):
        return not any(overlap(quad, corners(*o[1:6])) for o in self.obs + self.shared)

    def mirror_pt(self, x, y):
        return (x, H - y) if self.axis == 'y' else (W - x, y)

    def mirror_deg(self, d):
        d = -d if self.axis == 'y' else 180 - d
        d = (d + 180) % 360 - 180
        return 180 if d == -180 else d

    def full(self):
        """(starts, spots, obstacles) of the whole level."""
        mx = lambda x, y: self.mirror_pt(x, y)
        s2 = (*mx(self.start[0], self.start[1]), self.mirror_deg(self.start[2]))
        p2 = (*mx(self.spot[0], self.spot[1]), self.spot[2], self.spot[3], self.mirror_deg(self.spot[4]))
        obs = list(self.obs)
        for k, x, y, w, h, d, t in self.obs:
            nx, ny = mx(x, y)
            obs.append((k, nx, ny, w, h, self.mirror_deg(d) if k == 'car' else d, t))
        obs += self.shared
        # Normalise angles to (-180, 180]
        def norm(d):
            d = (d + 180) % 360 - 180
            return 180 if d == -180 else d
        s1 = (self.start[0], self.start[1], norm(self.start[2]))
        p1 = (*self.spot[:4], norm(self.spot[4]))
        return [s1, s2], [p1, p2], obs


# ------------------------------------------------------------------ the curve

def curve(n):
    """Target difficulty of level n (1..50): steady rise, each chapter's tenth level a notch up."""
    # Quicker rise at first (the opening levels teach, they should not bore), steady later
    d = 0.04 + 0.84 * ((n - 1) / 49) ** 0.8
    if n % 10 == 0:
        d += 0.03
    return min(1.0, d)


def geometry(D):
    """Bay, aisle and clutter for a difficulty."""
    return dict(
        BL=round(72 - 18 * D),        # bay length (car 44)
        BW=round(40 - 12 * D),        # bay width (car 22)
        AISLE=round(190 - 105 * D),   # lane in front of a row of bays
        GAP=round(150 - 75 * D),      # openings in walls
        CARS=int(1 + 7 * D),          # extra parked cars round the way
        CONES=int(2 + 9 * D),
    )


def tolerance(n):
    """Alignment tolerance of level n (Hop/Challenge.swift)."""
    t = min(1, (n + 6 - 1) / 49)
    return 0.27 - 0.21 * t


def reverse_rule(n, straight):
    return straight and n >= 9 and (n % 2 == 0 or n >= 30)


# ------------------------------------------------------------------ layouts (slot 0's half)

def row_of_bays(lv, rng, g, y_wall, facing, x0, x1, free_at, deg=90, keep=0.85):
    """Perpendicular bays against a wall at y_wall (facing -1: bays hang down from the top)."""
    BL, BW = g['BL'], g['BW']
    pitch = BW + 4
    yc = y_wall + facing * (BL / 2 + 4)
    xs = [x0 + i * pitch for i in range(int((x1 - x0) / pitch) + 1)]
    k = min(range(len(xs)), key=lambda i: abs(xs[i] - free_at))
    k = max(1, min(len(xs) - 2, k))
    for i, x in enumerate(xs):
        if i == k:
            continue
        if abs(i - k) == 1 or rng.random() < keep:
            # Parked a little off-centre, as people do
            lv.car(x + rng.uniform(-(BW - 22) / 3, (BW - 22) / 3), yc + rng.uniform(-3, 3), deg, rng)
    lv.spot = (xs[k], yc, BL, BW, deg)
    return yc


def L_open(lv, rng, g, D):
    lv.spot = (800, 375, g['BL'], g['BW'], 0)
    lv.start = (150, 375, 0)
    for x in (480, 520):
        lv.cone(x, 300)
    lv.car(800, 375 + g['BW'] / 2 + 16, 0, rng)


def L_perp(lv, rng, g, D):
    yc = row_of_bays(lv, rng, g, H - 4, -1, 230, 960, rng.uniform(520, 820))
    front = yc - g['BL'] / 2
    lane = front - g['AISLE'] / 2
    # A back-to-back row across the aisle where there is room
    other = front - g['AISLE'] - g['BL'] / 2
    if other - g['BL'] / 2 > 254:
        for x in range(250, 960, g['BW'] + 4):
            if rng.random() < 0.55 + 0.4 * D:
                lv.car(x, other, 90, rng)
    lv.start = (70, max(266, lane), 0)


def L_middle(lv, rng, g, D):
    """A gap in a line of cars parked end to end, open from the lane below."""
    y = 400
    gap = g['BL'] + 4
    x = 160
    bay_x = rng.uniform(460, 700)
    while x < 960:
        if lv.spot is None and x + gap / 2 > bay_x:
            lv.spot = (x + gap / 2, y, g['BL'], g['BW'], 0)
            x += gap + 2
        else:
            lv.car(x + 22, y, 0, rng)
            x += 44 + rng.uniform(4, 16 - 10 * D)
    # A row along the top wall leaves little room behind
    for xx in range(180, 960, 70):
        if rng.random() < 0.4 + 0.5 * D:
            lv.car(xx, H - 30, 0, rng)
    lv.start = (70, 290, 0)


def L_angled(lv, rng, g, D):
    a = 45 + 15 * D + rng.uniform(-3, 3)
    BL, BW = g['BL'], g['BW']
    sa, ca = math.sin(math.radians(a)), math.cos(math.radians(a))
    yc = H - 6 - (BL / 2) * sa - (BW / 2) * ca
    pitch = (BW + 4) / sa
    xs = [300 + i * pitch for i in range(int(640 / pitch))]
    k = rng.randrange(2, len(xs) - 2)
    for i, x in enumerate(xs):
        if i != k and (abs(i - k) == 1 or rng.random() < 0.85):
            lv.car(x, yc, a, rng)
    lv.spot = (xs[k], yc, BL, BW, a)
    lane = yc - (BL / 2) * sa - g['AISLE'] / 2
    lv.start = (70, max(266, lane), 0)


def L_around(lv, rng, g, D):
    """x-mirror: a divider across the lot; the bays are behind it, round its far end."""
    gap = max(60, g['GAP'] - 20)
    lv.wall((gap + 500) / 2, 250, 500 - gap, 16)
    # Bays along the bottom wall
    yc = row_of_bays(lv, rng, g, 4, 1, 120, 470, rng.uniform(300, 400))
    lv.start = (420, 390, 180)
    for _ in range(2 + int(3 * D)):
        lv.car(rng.uniform(150, 450), rng.uniform(300, 470), rng.choice([0, 90, 180]), rng)


def L_parallel(lv, rng, g, D, cones=False):
    """x-mirror: a curb along the bottom, cars parked end to end, a gap to reverse into."""
    lv.wall(250, 12, 500, 24)
    y = 24 + 4 + 11
    length = round(92 - 28 * D)
    width = round(34 - 6 * D)
    x = 30
    bay_x = rng.uniform(250, 360)
    while x < 470:
        if lv.spot is None and x + length / 2 > bay_x:
            lv.spot = (x + length / 2, 24 + 2 + width / 2, length, width, 0)
            x += length + 1
        else:
            lv.car(x + 22, y, 0, rng)
            x += 44 + rng.uniform(5, 14 - 6 * D)
    lane = round(130 - 55 * D)
    across = y + 11 + lane + 11
    for xx in range(60, 480, 58):
        if rng.random() < 0.6 + 0.35 * D:
            lv.car(xx, across, 0, rng)
    lv.start = (50, y + 11 + lane / 2 + 6, 0)
    if cones:
        # Slalom gates on the way in
        for j, xx in enumerate((150, 230)):
            for yy in range(int(across - 30), int(H - 20), 18):
                if abs(yy - (across + 60 if j % 2 else across + 150)) > 34:
                    lv.cone(xx, yy)
        lv.start = (50, min(H - 30, across + 100), 0)


def L_alcove(lv, rng, g, D):
    """Garage boxes along the top wall: three walls round each bay."""
    BL, BW = g['BL'], g['BW']
    inner = BW + 2
    depth = BL + 6
    t = 8
    pitch = inner + t
    count = int((960 - 260) / pitch)
    xs = [260 + i * pitch for i in range(count)]
    yc = H - 4 - depth / 2
    for i in range(count + 1):
        lv.wall(260 - pitch / 2 + i * pitch, yc, t, depth)
    k = rng.randrange(max(2, count // 3), count - 2)
    for i, x in enumerate(xs):
        if i != k and rng.random() < 0.9:
            lv.car(x, yc, 90, rng)
    lv.spot = (xs[k], yc - 2, BL, BW, 90)
    front = H - 4 - depth
    other = front - g['AISLE'] - 11
    if other > 262:
        for x in range(280, 960, 56):
            if rng.random() < 0.5 + 0.45 * D:
                lv.car(x, other, 0, rng)
    lv.start = (70, max(266, front - g['AISLE'] / 2), 0)


def L_maze(lv, rng, g, D):
    """Walled half; walls from alternate sides; the bay at the far end between parked cars."""
    lv.shared.append(('wall', 500, 250, 1000, 12, 0, 0))
    count = 2 + int(round(3 * D))
    gap = max(56, g['GAP'] - 30)
    xs = [230 + i * (560 / count) for i in range(count)]
    for i, x in enumerate(xs):
        length = 244 - gap
        if i % 2 == 0:
            lv.wall(x, H - length / 2, 18, length)
        else:
            lv.wall(x, 256 + length / 2, 18, length)
    BL, BW = g['BL'], g['BW']
    y = rng.uniform(310, 440)
    lv.spot = (W - 4 - BL / 2, y, BL, BW, 0)
    for k in (-1, 1):
        yy = y + k * (BW / 2 + 13)
        if 262 < yy < H - 12:
            lv.car(W - 4 - 24, yy, 0, rng)
    lv.start = (60, rng.choice([300, 440]), 0)


def L_pillars(lv, rng, g, D):
    """A garage deck: bays along the top wall, pillars at their mouths and down the aisle."""
    yc = row_of_bays(lv, rng, g, H - 4, -1, 230, 960, rng.uniform(500, 800), keep=0.9)
    front = yc - g['BL'] / 2
    BW = g['BW']
    for x in range(230 - (BW + 4) // 2, 960, (BW + 4) * 3):
        if abs(x - lv.spot[0]) > BW / 2 + 6:
            lv.wall(x, front - 10, 18, 18)
    lane = front - g['AISLE'] / 2
    for x in range(330, 900, 170):
        y = front - g['AISLE'] - 9
        if y > 262:
            lv.wall(x + rng.uniform(-15, 15), y, 22, 22)
    lv.start = (70, max(266, lane), 0)


def L_island(lv, rng, g, D):
    """Two bays at an odd angle in an island of parked cars, pillars round it."""
    ang = rng.choice([30, 60, 120, 150])
    a = math.radians(ang)
    across = (-math.sin(a), math.cos(a))
    cx, cy = rng.uniform(560, 700), 380
    pitch = g['BW'] + 4
    for k in range(-2, 3):
        x, y = cx + across[0] * k * pitch, cy + across[1] * k * pitch
        if k == 0:
            lv.spot = (x, y, g['BL'], g['BW'], ang)
        else:
            lv.car(x, y, ang, rng)
    for _ in range(int(3 + 4 * D)):
        t = rng.uniform(0, 2 * math.pi)
        x, y = cx + math.cos(t) * rng.uniform(110, 170), cy + math.sin(t) * rng.uniform(80, 110)
        if lv.inside_half(x, y, 20):
            lv.wall(x, y, 24, 24)
    lv.start = (70, 300, 0)


def L_turnaround(lv, rng, g, D):
    """Nose to a dead end: the bay is behind, past narrow passes."""
    lv.wall(W - 8, 375, 16, 250)
    BL, BW = g['BL'], g['BW']
    y = rng.uniform(320, 430)
    lv.spot = (8 + BL / 2, y, BL, BW, 0)
    for k in (-1, 1):
        yy = y + k * (BW / 2 + 13)
        if 262 < yy < H - 12:
            lv.car(8 + 24, yy, 0, rng)
    for x in (340 + rng.uniform(-30, 30), 520 + rng.uniform(-30, 30)):
        lv.wall(x, H - (60 + 70 * D) / 2, 18, 60 + 70 * D)
    lv.start = (W - 16 - 22 - (70 - 30 * D), rng.uniform(330, 420), 0)
    lv.shared.append(('wall', 820, 250, 340, 12, 0, 0))


def L_corridor(lv, rng, g, D):
    """A walled lane with a chicane, then a yard where the bay lies across the lane's end."""
    lw = round(118 - 38 * D)
    yc = 262 + lw / 2
    lv.shared.append(('wall', 400, 250, 800, 12, 0, 0))
    lv.wall(390, yc + lw / 2 + 6, 780, 12)
    bite = lw * (0.34 + 0.12 * D)
    for j, x in enumerate((330, 520)):
        side = 1 if j % 2 == 0 else -1
        lv.wall(x + rng.uniform(-20, 20), yc + side * (lw / 2 - bite / 2), 18, bite)
    BL, BW = g['BL'], g['BW']
    x = rng.uniform(880, 930)
    lv.spot = (x, H - 4 - BL / 2, BL, BW, 90)
    for k in (-1, 1):
        xx = x + k * (BW / 2 + 13)
        if xx < W - 12:
            lv.car(xx, H - 4 - 24, 90, rng)
    lv.start = (60, yc, 0)


def L_slalom(lv, rng, g, D):
    L_parallel(lv, rng, g, D, cones=True)


LAYOUTS = {
    'open': (L_open, 'y'), 'perp': (L_perp, 'y'), 'middle': (L_middle, 'y'), 'angled': (L_angled, 'y'),
    'around': (L_around, 'x'), 'parallel': (L_parallel, 'x'), 'alcove': (L_alcove, 'y'), 'maze': (L_maze, 'y'),
    'pillars': (L_pillars, 'y'), 'island': (L_island, 'y'), 'turnaround': (L_turnaround, 'y'),
    'corridor': (L_corridor, 'y'), 'slalom': (L_slalom, 'x'),
}

# Chapter plan: each chapter brings new layouts and replays the earlier ones tighter
PLAN = [
    'open', 'perp', 'middle', 'angled', 'around', 'perp', 'parallel', 'alcove', 'maze', 'pillars',
    'perp', 'parallel', 'angled', 'middle', 'island', 'alcove', 'around', 'turnaround', 'maze', 'corridor',
    'parallel', 'perp', 'island', 'angled', 'slalom', 'alcove', 'turnaround', 'middle', 'pillars', 'maze',
    'corridor', 'parallel', 'perp', 'island', 'turnaround', 'slalom', 'alcove', 'angled', 'pillars', 'maze',
    'perp', 'parallel', 'island', 'corridor', 'turnaround', 'alcove', 'slalom', 'angled', 'maze', 'pillars',
]

NAMES = {  # per layout, in order of use: TR, EN, ES
    'open': [("İlk Park", "First Park", "Primer aparcamiento")],
    'perp': [("Dik Park", "Turn In", "En batería"), ("Dar Yerler", "Tight Bays", "Plazas estrechas"),
             ("Ofis Otoparkı", "Office Lot", "Parking de oficinas"), ("Sıkışık Sıra", "Packed Row", "Fila llena"),
             ("Stadyum", "Stadium", "Estadio"), ("Havalimanı", "Airport", "Aeropuerto")],
    'middle': [("Araba Arası", "Between Cars", "Entre coches"), ("Orta Şerit", "Middle Lane", "Carril central"),
               ("İkili Sıra", "Double Row", "Doble fila")],
    'angled': [("Açılı Park", "Angled Bays", "Plazas en diagonal"), ("Çapraz Sıra", "Slanted Row", "Fila inclinada"),
               ("Balık Kılçığı", "Herringbone", "Espiga"), ("Eğik Kat", "Angled Deck", "Planta inclinada"),
               ("Sinema", "Cinema", "Cine")],
    'around': [("Etrafından Dolaş", "Go Around", "Rodea"), ("Hastane", "Hospital", "Hospital")],
    'parallel': [("Paralel Park", "Parallel Park", "Aparcamiento en línea"), ("Kaldırım Kenarı", "Curbside", "Junto a la acera"),
                 ("Sıkı Paralel", "Tight Parallel", "Línea ajustada"), ("Sahil Yolu", "Seaside Road", "Paseo marítimo"),
                 ("Dar Sokak", "Narrow Street", "Calle estrecha")],
    'alcove': [("Garaj", "Garage", "Garaje"), ("Yeraltı", "Underground", "Subterráneo"),
               ("Kule Otoparkı", "Tower Garage", "Garaje de la torre"), ("Depo", "Warehouse", "Almacén"),
               ("Otel Önü", "Hotel Drop", "Entrada del hotel")],
    'maze': [("Labirent", "Maze", "Laberinto"), ("Dolambaç", "Switchback", "Zigzag"), ("Labirent II", "Maze II", "Laberinto II"),
             ("Spiral", "Spiral", "Espiral"), ("Usta İşi", "Pro Move", "Maniobra pro")],
    'pillars': [("Kolonlu Kat", "Pillar Deck", "Planta de columnas"), ("AVM Otoparkı", "Mall Lot", "Parking del centro comercial"),
                ("Gece Vardiyası", "Night Shift", "Turno de noche"), ("Final: Kule", "Final: Tower", "Final: La torre")],
    'island': [("Pazar Yeri", "Market Square", "Plaza del mercado"), ("Kampüs", "Campus", "Campus"),
               ("Fuar Alanı", "Fairground", "Recinto ferial"), ("Liman", "Harbor", "Puerto")],
    'turnaround': [("Geri Manevra", "Back It In", "Marcha atrás"), ("Eski Şehir", "Old Town", "Casco antiguo"),
                   ("Tren Garı", "Station", "Estación"), ("Kıl Payı", "Hairline", "Por un pelo")],
    'corridor': [("Koni Koridoru", "Cone Corridor", "Pasillo de conos"), ("Servis Yolu", "Service Road", "Vía de servicio"),
                 ("Kavşak", "Junction", "Cruce")],
    'slalom': [("Konser", "Concert Night", "Noche de concierto"), ("Sıfır Hata", "Zero Margin", "Margen cero"),
               ("Şampiyon", "Champion", "Campeón")],
}


# ------------------------------------------------------------------ clutter

def clutter(lv, rng, g, D):
    """Parked cars and cones round the bay's approach and along the way (in slot 0's half),
    never in the bay's mouth or on the start."""
    sx, sy, sl, sw, sd = lv.spot
    a = math.radians(sd)
    keep_out = [corners(sx, sy, sl + 4, sw + 4, sd),
                # The bay's mouth on both ends
                corners(sx + math.cos(a) * (sl / 2 + 30), sy + math.sin(a) * (sl / 2 + 30), 60, sw + 10, sd),
                corners(sx - math.cos(a) * (sl / 2 + 30), sy - math.sin(a) * (sl / 2 + 30), 60, sw + 10, sd),
                corners(lv.start[0], lv.start[1], 120, 50, lv.start[2])]

    def add(kind, x, y, deg):
        w, h = CAR if kind == 'car' else (14, 14)
        q = corners(x, y, w + 8, h + 8, deg)
        if not all(lv.inside_half(px, py, 6) for px, py in q):
            return False
        if any(overlap(q, k) for k in keep_out) or not lv.free(q):
            return False
        if kind == 'car':
            lv.car(x, y, deg, rng)
        else:
            lv.cone(x, y)
        return True

    placed = 0
    for _ in range(g['CARS'] * 15):
        if placed >= g['CARS']:
            break
        r = rng.uniform(60, 200)
        t = rng.uniform(0, 2 * math.pi)
        deg = rng.choice([0, 90, sd, sd + 90, rng.uniform(0, 180)])
        placed += add('car', sx + math.cos(t) * r, sy + math.sin(t) * r, deg)
    placed = 0
    for _ in range(g['CONES'] * 12):
        if placed >= g['CONES']:
            break
        if rng.random() < 0.6:
            x, y = sx + rng.uniform(-150, 150), sy + rng.uniform(-120, 120)
        else:
            x, y = rng.uniform(120, 900), rng.uniform(20, 480)
        placed += add('cone', x, y, 0)


# ------------------------------------------------------------------ measuring

MARGINS = [1, 3, 6, 10, 15]


def measure(lv, n):
    """Planner run for slot 0 (slot 1 is its mirror). None if it cannot be parked."""
    starts, spots, obs = lv.full()
    start, spot = starts[0], spots[0]
    straight = all(abs(abs(s[4]) - 90) < 3 for s in spots)
    reverse = reverse_rule(n, straight)
    a = math.radians(spot[4])
    axis = (math.cos(a), math.sin(a))
    outward = 1 if (start[0] - spot[0]) * axis[0] + (start[1] - spot[1]) * axis[1] >= 0 else -1
    out = (axis[0] * outward, axis[1] * outward)
    tol = tolerance(n)
    # Both starts must be clear of each other and of everything
    if overlap(corners(starts[0][0], starts[0][1], 50, 28, starts[0][2]), corners(starts[1][0], starts[1][1], 50, 28, starts[1][2])):
        return None
    if overlap(corners(*spots[0]), corners(*spots[1])):
        return None
    for s in spots:
        q = corners(*s)
        if any(not (2 <= x <= W - 2 and 2 <= y <= H - 2) for x, y in q):
            return None
        if any(overlap(q, corners(*o[1:6])) for o in obs):
            return None
    base = None
    room = 0
    for m in MARGINS:
        occ, dist = planner.raster(obs, margin=m)
        # The bay itself is never narrowed (its slack is measured on its own)
        if m > 1:
            import numpy as np
            ys, xs = np.mgrid[0:H, 0:W]
            bx, by, bl, bw, bd = spot
            c, s = math.cos(math.radians(bd)), math.sin(math.radians(bd))
            lx = np.abs((xs + 0.5 - bx) * c + (ys + 0.5 - by) * s)
            ly = np.abs(-(xs + 0.5 - bx) * s + (ys + 0.5 - by) * c)
            inside = (lx <= bl / 2) & (ly <= bw / 2)
            occ[inside & (base_occ == 0)] = 0
        else:
            base_occ = occ.copy()
        r = planner.plan(occ, dist, start, spot, tol, reverse=reverse, out_dir=out,
                         budget=900_000 if m == 1 else 450_000)
        if r is None:
            break
        if m == 1:
            base = r
        room = m
    # More than four changes between drive and reverse is a chore on a phone, not a challenge
    if base is None or base['switches'] > 4:
        return None
    slack = (spot[2] - 44) + (spot[3] - 22) * 1.5
    s_slack = min(1, max(0, (55 - slack) / 36))
    s_room = min(1, max(0, (15 - room) / 14))
    s_moves = min(1, base['switches'] / 3)
    s_way = min(1, max(0, (base['length'] - 300) / 1300))
    score = 0.34 * s_slack + 0.30 * s_room + 0.22 * s_moves + 0.14 * s_way
    return dict(score=score, room=room, switches=base['switches'], length=base['length'], slack=slack,
                reverse=reverse, starts=starts, spots=spots, obs=obs)


def design(n, tries=10):
    kind = PLAN[n - 1]
    fn, axis = LAYOUTS[kind]
    target = curve(n)
    best = None
    for attempt in range(tries * 6):
        if attempt >= tries and best is not None:
            break
        rng = random.Random(n * 7919 + attempt * 104729)
        # Geometry nudged round the target so the measured score can land on the curve; once a
        # candidate is measured the next ones lean the other way from its error
        lean = 0 if best is None else (target - best['score'])
        D = min(1, max(0, best['D'] + lean * 1.4 + rng.uniform(-0.05, 0.05) if best else target + rng.uniform(-0.06, 0.06)))
        g = geometry(D)
        lv = Level(axis)
        try:
            fn(lv, rng, g, D)
        except (ValueError, IndexError):
            continue
        if lv.spot is None or lv.start is None:
            continue
        if n > 1:
            clutter(lv, rng, g, D)
        m = measure(lv, n)
        if m is None:
            continue
        m['D'] = D
        if best is None or abs(m['score'] - target) < abs(best['score'] - target):
            best = m
        if abs(best['score'] - target) < 0.025:
            break
    if best is None:
        raise SystemExit(f'level {n}: no solvable design')
    return best


# ------------------------------------------------------------------ output

def swift(name, m):
    tr, en, es = name
    starts = ', '.join(f'start({x:.0f}, {y:.0f}, {d:.0f})' for x, y, d in m['starts'])
    spots = ', '.join(f'spot({x:.0f}, {y:.0f}, {w:.0f}, {h:.0f}, {d:.0f})' for x, y, w, h, d in m['spots'])
    obs = []
    for kind, x, y, w, h, d, tint in m['obs']:
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


def names():
    used = {k: 0 for k in NAMES}
    out = []
    for kind in PLAN:
        out.append(NAMES[kind][used[kind]])
        used[kind] += 1
    return out


def main():
    path = sys.argv[1]
    first, last = (int(sys.argv[2]), int(sys.argv[3])) if len(sys.argv) > 3 else (1, 50)
    cache_path = os.environ.get('LEVEL_CACHE', '/tmp/level_designs.json')
    cache = json.load(open(cache_path)) if os.path.exists(cache_path) else {}
    for n in range(first, last + 1):
        m = design(n, tries=int(os.environ.get('TRIES', 10)))
        old = cache.get(str(n))
        if old and os.environ.get('KEEP_BEST') and abs(old['score'] - curve(n)) < abs(m['score'] - curve(n)):
            m = old
        cache[str(n)] = m
        json.dump(cache, open(cache_path, 'w'))
        print(f"{n:2d} {PLAN[n - 1]:10s} target {curve(n):.2f} score {m['score']:.2f}  bay {m['spots'][0][2]:.0f}x{m['spots'][0][3]:.0f} "
              f"room {m['room']:2d} moves {m['switches']} way {m['length']:.0f}{' back-in' if m['reverse'] else ''}", flush=True)
    if len(cache) < 50:
        return
    nm = names()
    body = ',\n\n'.join(swift(nm[n - 1], cache[str(n)]) for n in range(1, 51))
    spanish = '\n'.join(f'        "{en}": "{es}",' for tr, en, es in nm)
    out = f'''import CoreGraphics

// Generated by tools/design_levels.py: the 50 parking levels on a measured difficulty curve (each
// solved by a planner driving the game's car). Do not edit by hand; change the script and run it.

extension Levels {{
    static let moreSpanishNames: [String: String] = [
{spanish}
    ]

    static let more: [LevelDef] = [
{body}
    ]
}}
'''
    open(path, 'w').write(out)


if __name__ == '__main__':
    main()
