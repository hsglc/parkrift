"""Which surface each face of a Polyfork car is, from its colour and the car's colour knobs
(params.json). Shared by tools/convert_polyfork_cars.py and the preview renderer.

Classes: paint (tinted by the player's paint; `grey` is the base level), glass, chrome, dark
(rubber, grilles, recesses), headlight, taillight, other (keeps its own colour).
"""
import numpy as np

GLASS = {'glass'}
CHROME = {'chrome', 'steel', 'rim', 'brightwork'}
DARK = {'tire', 'blackout', 'recess', 'wells', 'dark', 'grille', 'pan', 'underbody'}
KIT = {'glass': '#2a2d35', 'chrome': '#e2e4e7', 'steel': '#dadde0', 'tire': '#1a1f26', 'blackout': '#0c0e14',
       'brightwork': '#c2c7cd', 'rim': '#afb5bb', 'grille': '#3d3f46', 'pan': '#4c4f57'}
HEADLIGHT = ['#ecf1cb', '#e7eaea', '#cfd6d6']
TAILLIGHT = ['#d13d34', '#b9553f']


def hex255(h):
    return np.array([int(h[i:i + 2], 16) for i in (1, 3, 5)], dtype=np.float64)


def snap(colors255, palette255):
    """Each colour to the nearest colour of the original model (bevel faces blend neighbours)."""
    d = np.linalg.norm(colors255[:, None, :] - palette255[None, :, :], axis=2)
    return palette255[np.argmin(d, axis=1)]


def classify(colors255, centres_x, length, knobs, paint, recolor):
    """colors255: (n, 3) sRGB 0-255 per face; centres_x: face centre along the car (+ front).
    Returns (classes, base colours (n, 3) for the palette, grey level for painted faces)."""
    n = len(colors255)
    classes = np.array(['other'] * n, dtype=object)
    base = colors255.copy()

    def near(h, tol=4.5):
        return np.linalg.norm(colors255 - hex255(h), axis=1) < tol

    # The kit's shared colours, for cars whose params do not list them (a car's own knob wins)
    used = {v.lower() for v in knobs.values()}
    merged = dict(knobs)
    for name, value in KIT.items():
        if name not in merged and value not in used:
            merged[name] = value
    for name, value in merged.items():
        hit = near(value)
        if name in GLASS:
            classes[hit] = 'glass'
        elif name in CHROME or (name == 'trim' and min(hex255(value)) > 200 and np.ptp(hex255(value)) < 12):
            classes[hit] = 'chrome'
        elif name in DARK or (name == 'trim' and max(hex255(value)) < 90):
            classes[hit] = 'dark'
    for name, grey in paint.items():
        hit = near(knobs[name])
        classes[hit] = 'paint'
        base[hit] = grey * 255
    for name, colour in recolor.items():
        hit = near(knobs[name])
        classes[hit] = 'dark'
        base[hit] = hex255(colour)
    head = np.zeros(n, dtype=bool)
    for h in HEADLIGHT:
        head |= near(h, 6)
    tail = np.zeros(n, dtype=bool)
    for h in TAILLIGHT:
        tail |= near(h, 6)
    classes[head & (centres_x > length * 0.25)] = 'headlight'
    classes[tail & (centres_x < -length * 0.3)] = 'taillight'
    return classes, base
