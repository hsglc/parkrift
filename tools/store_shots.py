"""App Store screenshots: each real in-game screenshot framed on a dark neon background with a
short caption per language. The game image is shown whole and unchanged (only scaled), so the
screenshots stay true to the app; captions only name what the shot shows.

Usage: python3 store_shots.py <folder with raw shots> <output folder> [width height]
Writes <output>/<locale>/NN-name.png for en-US, tr and es-ES.
"""
import os, sys, glob
from PIL import Image, ImageDraw, ImageFilter, ImageFont

SRC, OUT = sys.argv[1], sys.argv[2]
W, H = (int(sys.argv[3]), int(sys.argv[4])) if len(sys.argv) > 4 else (2868, 1320)

# raw shot name -> captions (kicker, headline, line) per locale
SHOTS = [
    ('home', {
        'en-US': ('PARK · DRIFT · ONLINE', 'Park, drift and race', 'Solo levels, city races and online duels'),
        'tr': ('PARK · DRİFT · ONLINE', 'Park et, drift at, yarış', 'Tek kişilik bölümler, şehir yarışları, online düellolar'),
        'es-ES': ('APARCA · DERRAPA · ONLINE', 'Aparca, derrapa y compite', 'Niveles, carreras urbanas y duelos online')}),
    ('city-shot-hud', {
        'en-US': ('POLICE CHASES', 'Outrun the police', 'Crash or speed and the sirens come for you'),
        'tr': ('POLİS KOVALAMACASI', 'Polisten kaç', 'Kaza yap ya da hız yap, siren peşine düşer'),
        'es-ES': ('PERSECUCIONES', 'Escapa de la policía', 'Choca o corre demasiado y te persiguen')}),
    ('garage', {
        'en-US': ('GARAGE', '6 original cars', 'Paint, rims and upgrades'),
        'tr': ('GARAJ', '6 özgün araba', 'Boya, jant ve geliştirmeler'),
        'es-ES': ('GARAJE', '6 coches originales', 'Pintura, llantas y mejoras')}),
    ('levels', {
        'en-US': ('PARKING CAREER', '50 levels, each one harder', 'Time limits, tight bays and patrol cars'),
        'tr': ('PARK KARİYERİ', 'Her biri daha zor 50 bölüm', 'Süre sınırı, dar park yerleri, devriye araçlar'),
        'es-ES': ('CARRERA DE APARCAMIENTO', '50 niveles cada vez más difíciles', 'Límite de tiempo, plazas estrechas y patrullas')}),
]

CYAN = (64, 235, 255)
MAGENTA = (255, 77, 184)
INK = (8, 9, 15)


def font(names, size):
    """A bold condensed system font (macOS runner), or the default one."""
    for path, wanted in names:
        if not os.path.exists(path):
            continue
        for index in range(0, 24):
            try:
                f = ImageFont.truetype(path, size, index=index)
            except Exception:
                break
            name = ' '.join(f.getname()).lower()
            if all(w in name for w in wanted):
                return f
    for fallback in ['/System/Library/Fonts/Supplemental/Arial Bold.ttf',
                     '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf']:
        if os.path.exists(fallback):
            return ImageFont.truetype(fallback, size)
    return ImageFont.load_default()


HEAVY = [('/System/Library/Fonts/Avenir Next Condensed.ttc', ['heavy', 'italic']),
         ('/System/Library/Fonts/Avenir Next Condensed.ttc', ['bold', 'italic']),
         ('/System/Library/Fonts/Supplemental/Futura.ttc', ['condensed', 'extrabold'])]
DEMI = [('/System/Library/Fonts/Avenir Next.ttc', ['demi', 'bold']),
        ('/System/Library/Fonts/Avenir Next.ttc', ['medium'])]
WIDE = [('/System/Library/Fonts/Avenir Next.ttc', ['heavy']),
        ('/System/Library/Fonts/Avenir Next.ttc', ['bold'])]


def background():
    bg = Image.new('RGB', (W, H), INK)
    glow = Image.new('RGB', (W, H), (0, 0, 0))
    d = ImageDraw.Draw(glow)
    d.ellipse((-W * 0.15, -H * 0.6, W * 0.45, H * 0.7), fill=(10, 70, 90))
    d.ellipse((W * 0.6, H * 0.3, W * 1.2, H * 1.6), fill=(85, 18, 70))
    glow = glow.filter(ImageFilter.GaussianBlur(H * 0.25))
    return Image.blend(bg, glow, 0.85)


def compose(shot, kicker, headline, line):
    canvas = background()
    draw = ImageDraw.Draw(canvas)
    top = int(H * 0.29)
    # Caption band: kicker with a neon dash, big italic headline, a quieter line
    k_font = font(WIDE, int(H * 0.028))
    h_font = font(HEAVY, int(H * 0.085))
    l_font = font(DEMI, int(H * 0.032))
    margin = int(W * 0.05)
    y = int(H * 0.045)
    draw.rectangle((margin, y + k_font.size // 2 - 3, margin + 60, y + k_font.size // 2 + 3), fill=CYAN)
    draw.text((margin + 80, y), kicker, font=k_font, fill=CYAN)
    hy = y + int(k_font.size * 1.5)
    draw.text((margin, hy), headline, font=h_font, fill=(255, 255, 255))
    draw.text((margin + 4, hy + int(h_font.size * 1.12)), line, font=l_font, fill=(190, 196, 210))
    # The real game screen, whole, with rounded corners, a soft shadow and a thin neon edge
    area_h = H - top - int(H * 0.05)
    scale = min(area_h / shot.height, (W - 2 * margin) / shot.width)
    sw, sh = int(shot.width * scale), int(shot.height * scale)
    shot = shot.resize((sw, sh), Image.LANCZOS)
    x0 = (W - sw) // 2
    y0 = top
    radius = int(sh * 0.05)
    mask = Image.new('L', (sw, sh), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, sw - 1, sh - 1), radius=radius, fill=255)
    shadow = Image.new('L', (W, H), 0)
    ImageDraw.Draw(shadow).rounded_rectangle((x0 + 10, y0 + 24, x0 + sw + 10, y0 + sh + 24), radius=radius, fill=170)
    shadow = shadow.filter(ImageFilter.GaussianBlur(28))
    canvas.paste(Image.new('RGB', (W, H), (0, 0, 0)), (0, 0), shadow)
    canvas.paste(shot, (x0, y0), mask)
    edge = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    e = ImageDraw.Draw(edge)
    e.rounded_rectangle((x0 - 2, y0 - 2, x0 + sw + 2, y0 + sh + 2), radius=radius + 2, outline=CYAN + (150,), width=3)
    canvas = Image.alpha_composite(canvas.convert('RGBA'), edge).convert('RGB')
    return canvas


def main():
    made = 0
    for locale in ['en-US', 'tr', 'es-ES']:
        os.makedirs(os.path.join(OUT, locale), exist_ok=True)
        n = 0
        for name, captions in SHOTS:
            # Shots taken with the game in this language (raw/en, raw/tr, raw/es), else any
            lang = {'en-US': 'en', 'tr': 'tr', 'es-ES': 'es'}[locale]
            path = os.path.join(SRC, lang, name + '.png')
            if not os.path.exists(path):
                path = os.path.join(SRC, name + '.png')
            if not os.path.exists(path):
                print('missing', name)
                continue
            shot = Image.open(path).convert('RGB')
            if shot.height > shot.width:
                shot = shot.rotate(90, expand=True)
            # Landscape simulator shots keep the Dynamic Island as a black pill on the left
            # edge; trim that strip (a plain crop, the game image itself is untouched).
            cut = int(shot.width * 0.056)
            shot = shot.crop((cut, 0, shot.width, shot.height))
            n += 1
            compose(shot, *captions[locale]).save(os.path.join(OUT, locale, f'{n:02d}-{name}.png'))
            made += 1
    print('store shots', made)


if __name__ == '__main__':
    main()
