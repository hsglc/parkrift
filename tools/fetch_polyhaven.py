"""Downloads the Poly Haven (CC0) textures and models used by the parking venues.

Textures: <out>/tex/<name>_{diff,nor,rough}.jpg at 2K (normal maps in OpenGL convention).
Models:   <out>/models/<name>/<name>.gltf with its .bin and 1K textures.

Usage: python3 fetch_polyhaven.py <out dir>
"""
import json, os, sys, urllib.request

OUT = sys.argv[1]
TEXTURES = ['container_side', 'corrugated_iron_02', 'concrete_floor_painted', 'hangar_concrete_floor',
            'rectangular_facade_tiles', 'painted_metal_shutter', 'wood_floor_deck', 'concrete_wall_001']
MODELS = ['street_lamp_02', 'Barrel_01', 'wooden_crate_01', 'concrete_road_barrier_02', 'planter_box_01',
          'modular_street_seating', 'dutch_ship_medium']


HEADERS = {'User-Agent': 'parkrift-asset-fetch/1.0'}


def get(url, path):
    if os.path.exists(path):
        return
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with urllib.request.urlopen(urllib.request.Request(url, headers=HEADERS), timeout=120) as r, open(path, 'wb') as f:
        f.write(r.read())
    print('  ', os.path.basename(path), os.path.getsize(path) // 1024, 'KB', flush=True)


def files(asset):
    with urllib.request.urlopen(urllib.request.Request(f'https://api.polyhaven.com/files/{asset}', headers=HEADERS), timeout=60) as r:
        return json.load(r)


for name in TEXTURES:
    print(name, flush=True)
    f = files(name)
    for key, short in (('Diffuse', 'diff'), ('nor_gl', 'nor'), ('Rough', 'rough')):
        get(f[key]['2k']['jpg']['url'], os.path.join(OUT, 'tex', f'{name}_{short}.jpg'))

for name in MODELS:
    print(name, flush=True)
    g = files(name)['gltf']['1k']['gltf']
    folder = os.path.join(OUT, 'models', name)
    get(g['url'], os.path.join(folder, name + '.gltf'))
    for rel, item in g['include'].items():
        get(item['url'], os.path.join(folder, rel))
