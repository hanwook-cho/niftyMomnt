#!/usr/bin/env python3
import os
from PIL import Image

INPUT = os.path.join('Apps', 'Piqd', 'app_icon.png')
OUT_DIR = os.path.join('Apps', 'Piqd', 'Piqd', 'Assets.xcassets', 'AppIcon.appiconset')
OUT_NAME = 'Icon-1024.png'
OUT_PATH = os.path.join(OUT_DIR, OUT_NAME)

os.makedirs(OUT_DIR, exist_ok=True)

def make_transparent(img, threshold=240):
    img = img.convert('RGBA')
    px = img.load()
    w,h = img.size
    for y in range(h):
        for x in range(w):
            r,g,b,a = px[x,y]
            # treat near-white/very-light pixels as background
            m = max(r,g,b)
            if m >= threshold:
                # compute soft alpha for smooth edges
                alpha = int(255 * (1 - (m - threshold) / (255 - threshold)))
                alpha = max(0, min(255, alpha))
                px[x,y] = (r,g,b,alpha)
            else:
                px[x,y] = (r,g,b,255)
    return img

def center_crop_to_square(img):
    w,h = img.size
    side = min(w,h)
    left = (w - side) // 2
    top = (h - side) // 2
    return img.crop((left, top, left+side, top+side))

def main():
    if not os.path.exists(INPUT):
        print('Input not found:', INPUT)
        return 2
    img = Image.open(INPUT)
    img = center_crop_to_square(img)
    img = make_transparent(img, threshold=240)
    img = img.resize((1024,1024), Image.LANCZOS)
    img.save(OUT_PATH, format='PNG')
    print('Wrote', OUT_PATH)
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
