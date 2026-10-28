"""Adds parked cars and cones round the bays of the hand-made parking levels 1-10
(Hop/Levels.swift), with the same rules as the generated levels (tools/make_levels.py):
each one is kept only if both cars can still reach their bays with room for a real car, none
blocks a bay's entry or a start, and none touches another obstacle. Run once; the added items
are written into the level definitions.

Usage: python3 clutter_first_levels.py <Hop/Levels.swift>
"""
import re, sys, random, importlib.util, os

here = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location('make_levels', os.path.join(here, 'make_levels.py'))
ml = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ml)

path = sys.argv[1]
text = open(path).read()
start = text.index('    static let base: [LevelDef] = [')
end = text.index('\n    ]\n', start)
block = text[start:end]
num = r'(-?\d+(?:\.\d+)?)'
out = block
for index, m in enumerate(re.finditer(r'LevelDef\(nameTR: "[^"]*", nameEN: "[^"]*",(.*?)obstacles: \[(.*?)\]\)', block, re.S)):
    body, obstacles = m.group(1), m.group(2)
    lv = ml.Level(('', '', ''))
    for s in re.finditer(rf'start\({num}, {num}(?:, {num})?\)', body):
        lv.starts.append((float(s.group(1)), float(s.group(2)), float(s.group(3) or 0)))
    for s in re.finditer(rf'spot\({num}, {num}, {num}, {num}(?:, {num})?\)', body):
        lv.spots.append(tuple(float(v) for v in s.groups()[:4]) + (float(s.group(5) or 0),))
    for o in re.finditer(rf'(car|cone|wall)\(([^)]*)\)', obstacles):
        v = [float(x) for x in o.group(2).split(',')]
        if o.group(1) == 'car':
            lv.car(v[0], v[1], v[2] if len(v) > 2 else 0, int(v[3]) if len(v) > 3 else 0)
        elif o.group(1) == 'cone':
            lv.cone(v[0], v[1])
        else:
            lv.wall(*v)
    if lv.check() is not None:
        print(f'level {index + 1}: does not check out as written ({lv.check()}), left as is')
        continue
    before = len(lv.obs)
    rng = random.Random(4242 + index)
    level = index + 1
    cars, cones = ml.clutter(lv, rng, level / 10, cars=1 + level // 2, cones=2 + level // 2)
    added = []
    for kind, x, y, w, h, d, tint in lv.obs[before:]:
        added.append(f'car({x:.0f}, {y:.0f}, {d:.0f}, {tint})' if kind == 'car' else f'cone({x:.0f}, {y:.0f})')
    print(f'level {level}: +{cars} cars, +{cones} cones')
    if added:
        old = m.group(0)
        new = old[:-2] + ',\n                             ' + ', '.join(added) + '])'
        out = out.replace(old, new, 1)
open(path, 'w').write(text[:start] + out + text[end:])
