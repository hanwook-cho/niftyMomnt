#!/usr/bin/env python3
import os
import json
from PIL import Image

ICONSET_DIR = os.path.join('Apps', 'Piqd', 'Piqd', 'Assets.xcassets', 'AppIcon.appiconset')
SRC = os.path.join(ICONSET_DIR, 'Icon-1024.png')

# Standard set of icons used by Xcode AppIcon (subset for iOS)
IMAGES = [
    {"size": "20x20", "idiom": "iphone", "scales": [2,3], "role": None, "filename": None},
    {"size": "29x29", "idiom": "iphone", "scales": [2,3], "role": None, "filename": None},
    {"size": "40x40", "idiom": "iphone", "scales": [2,3], "role": None, "filename": None},
    {"size": "60x60", "idiom": "iphone", "scales": [2,3], "role": None, "filename": None},
    {"size": "20x20", "idiom": "ipad", "scales": [1,2], "role": None, "filename": None},
    {"size": "29x29", "idiom": "ipad", "scales": [1,2], "role": None, "filename": None},
    {"size": "40x40", "idiom": "ipad", "scales": [1,2], "role": None, "filename": None},
    {"size": "76x76", "idiom": "ipad", "scales": [1,2], "role": None, "filename": None},
    {"size": "83.5x83.5", "idiom": "ipad", "scales": [2], "role": None, "filename": None},
    {"size": "1024x1024", "idiom": "ios-marketing", "scales": [1], "role": None, "filename": None},
]

def ensure_dir():
    os.makedirs(ICONSET_DIR, exist_ok=True)

def size_to_px(size_str, scale):
    # size_str like '20x20' or '83.5x83.5'
    w = float(size_str.split('x')[0])
    return int(round(w * scale))

def make_icons():
    if not os.path.exists(SRC):
        print('Source 1024 image not found at', SRC)
        return 2
    src_img = Image.open(SRC).convert('RGBA')
    images_json = []
    for item in IMAGES:
        for scale in item['scales']:
            px = size_to_px(item['size'], scale)
            out_name = f"icon_{item['size'].replace('.','_')}_{scale}x.png"
            out_path = os.path.join(ICONSET_DIR, out_name)
            img = src_img.resize((px, px), Image.LANCZOS)
            img.save(out_path, format='PNG')
            entry = {
                "size": item['size'],
                "idiom": item['idiom'],
                "filename": out_name,
                "scale": f"{scale}x"
            }
            images_json.append(entry)

    contents = {"images": images_json, "info": {"version": 1, "author": "xcode"}}
    with open(os.path.join(ICONSET_DIR, 'Contents.json'), 'w') as f:
        json.dump(contents, f, indent=2, sort_keys=True)
    print('Wrote', os.path.join(ICONSET_DIR, 'Contents.json'))
    return 0

def main():
    ensure_dir()
    return make_icons()

if __name__ == '__main__':
    raise SystemExit(main())
