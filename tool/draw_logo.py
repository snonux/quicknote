"""Draws the TurboNotes logo: logo.png, logo-small.png, icon.png, the adaptive
launcher foreground (logo-foreground.png) and the F-Droid store icon.

Needs Pillow. Run from the repository root, then regenerate the Android
launcher icons with `dart run flutter_launcher_icons`.
"""
from PIL import Image, ImageDraw, ImageFilter

S = 2400

def lerp(a, b, t): return tuple(int(a[i] + (b[i]-a[i])*t) for i in range(3))

def background():
    top, bottom = (0, 121, 107), (0, 51, 56)
    img = Image.new('RGBA', (S, S))
    d = ImageDraw.Draw(img)
    for y in range(S):
        d.line([(0, y), (S, y)], fill=lerp(top, bottom, y / S) + (255,))
    return img

def motif(scale=1.0):
    """The note page, drawn on a transparent S x S canvas, centered."""
    layer = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    w, h = 1300 * scale, 1640 * scale
    # Shifted right of center to leave room for the speed streaks.
    x0, y0 = (S - w) / 2 + 300 * scale, (S - h) / 2
    fold = 380 * scale
    r = 90 * scale
    # shadow
    sh = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    sd = ImageDraw.Draw(sh)
    off = 40 * scale
    sd.rounded_rectangle([x0 + off, y0 + off * 1.6, x0 + w + off, y0 + h + off * 1.6], r, fill=(0, 0, 0, 110))
    sh = sh.filter(ImageFilter.GaussianBlur(45 * scale))
    layer.alpha_composite(sh)
    # page with the top-right corner cut off
    page = Image.new('L', (S, S), 0)
    pd = ImageDraw.Draw(page)
    pd.rounded_rectangle([x0, y0, x0 + w, y0 + h], r, fill=255)
    pd.polygon([(x0 + w - fold, y0 - 2), (x0 + w + 2, y0 - 2), (x0 + w + 2, y0 + fold)], fill=0)
    white = Image.new('RGBA', (S, S), (250, 252, 251, 255))
    layer.paste(white, (0, 0), page)
    d = ImageDraw.Draw(layer)
    # the fold
    d.polygon([(x0 + w - fold, y0), (x0 + w - fold, y0 + fold - r*0.2), (x0 + w - r*0.2, y0 + fold)],
              fill=(178, 223, 219, 255))
    d.line([(x0 + w - fold, y0), (x0 + w, y0 + fold)], fill=(128, 203, 196, 255), width=int(10 * scale))
    teal, amber, grey = (0, 121, 107, 255), (255, 179, 0, 255), (176, 190, 197, 255)
    lw = 70 * scale
    cx = x0 + 170 * scale
    # an amber lightning bolt, the "turbo"
    hy = y0 + 250 * scale
    hs = 330 * scale
    bolt = [(0.62, 0.0), (0.10, 0.58), (0.44, 0.58), (0.30, 1.0), (0.90, 0.36), (0.55, 0.36), (0.72, 0.0)]
    d.polygon([(cx + bx * hs * 0.8, hy + by * hs) for bx, by in bolt], fill=amber)
    # heading bar next to it
    hx = cx + hs * 0.8 + 70 * scale
    d.rounded_rectangle([hx, hy + hs/2 - lw*0.75, x0 + w - fold - 40*scale, hy + hs/2 + lw*0.75], lw*0.75, fill=teal)
    # body lines
    ly = y0 + 760 * scale
    for i, frac in enumerate((0.95, 0.8, 0.9)):
        yy = ly + i * 175 * scale
        d.rounded_rectangle([cx, yy, cx + (w - 340*scale) * frac, yy + lw], lw/2, fill=grey)
    # a done task: amber box with a check
    ty = ly + 3 * 175 * scale + 40*scale
    bs = 150 * scale
    d.rounded_rectangle([cx, ty, cx + bs, ty + bs], 30*scale, fill=amber)
    d.line([(cx + bs*0.22, ty + bs*0.52), (cx + bs*0.43, ty + bs*0.74), (cx + bs*0.8, ty + bs*0.28)],
           fill=(255, 255, 255, 255), width=int(30*scale), joint='curve')
    d.rounded_rectangle([cx + bs + 70*scale, ty + bs/2 - lw/2, cx + (w - 340*scale)*0.7, ty + bs/2 + lw/2], lw/2, fill=grey)
    # speed streaks trailing off the left edge of the page
    streak = (255, 255, 255, 200)
    for i, (dy, length) in enumerate(((0.30, 420), (0.50, 560), (0.70, 380))):
        yy = y0 + h * dy
        sw = 64 * scale
        d.rounded_rectangle([x0 - (length + 60) * scale, yy - sw / 2, x0 - 60 * scale, yy + sw / 2],
                            sw / 2, fill=streak)
    return layer

full = background()
full.alpha_composite(motif(0.85))
full.resize((600, 600), Image.LANCZOS).save('logo.png')
full.resize((300, 300), Image.LANCZOS).save('logo-small.png')
full.resize((64, 64), Image.LANCZOS).save('icon.png')
# store listing icon (F-Droid)
full.resize((512, 512), Image.LANCZOS).save('fastlane/metadata/android/en-US/images/icon.png')
# adaptive foreground: motif inside the 66% safe zone, transparent
fg = motif(0.64)
fg.resize((1024, 1024), Image.LANCZOS).save('logo-foreground.png')
