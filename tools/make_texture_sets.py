"""Moves big model textures into the asset catalog as texture sets, so Xcode stores them
GPU-compressed (ASTC 4x4: the full 2K resolution at a quarter of the memory of plain RGBA, with
mipmaps made at build time). The game loads them with MTKTextureLoader (Scenery.texture).

Colour maps (*_diff) are sRGB colours; normal and roughness maps are data.

Usage: python3 make_texture_sets.py <Hop/Assets.xcassets> <image> [<image> ...]
       (each image is moved into <name>.textureset/Universal.mipmapset/)
"""
import json, os, shutil, sys

catalog = sys.argv[1]
for path in sys.argv[2:]:
    name, ext = os.path.splitext(os.path.basename(path))
    colour = name.endswith('_diff')
    folder = os.path.join(catalog, name + '.textureset')
    mips = os.path.join(folder, 'Universal.mipmapset')
    if os.path.isdir(folder):
        shutil.rmtree(folder)
    os.makedirs(mips)
    shutil.move(path, os.path.join(mips, name + ext))
    with open(os.path.join(folder, 'Contents.json'), 'w') as f:
        json.dump({
            'info': {'author': 'xcode', 'version': 1},
            'properties': {'interpretation': 'colors' if colour else 'data'},
            'textures': [{
                'filename': 'Universal.mipmapset',
                'idiom': 'universal',
                'pixel-format': 'astc-4x4-sRGB' if colour else 'astc-4x4',
            }],
        }, f, indent=2)
    with open(os.path.join(mips, 'Contents.json'), 'w') as f:
        json.dump({
            'info': {'author': 'xcode', 'version': 1},
            'properties': {'level-mode': 'all'},
            'levels': [{'filename': name + ext, 'mipmap-level': 'base'}],
        }, f, indent=2)
    print('texture set', name)
