"""Hanj brand asset export — v2.

Adds what v1 missed, per the agent's LOGO-BRIEF report:
  - ic_launcher_background.png at #0D0B09, five densities (v1 emitted none;
    the existing layer was #14110F, a different near-black)
  - assets/icon/ generator inputs so re-running flutter_launcher_icons
    reproduces this mark instead of reverting to the serif H
  - mipmap ic_launcher_foreground / ic_launcher_round overwritten rather
    than left as the old ivory wing
  - Flutter inline asset named hanj_wing_transparent.png, which is what the
    nine live sites actually reference
  - a real two-stroke vector master, so re-exporting the favicon can't
    silently yield three strokes

Destination paths are PROJECT-RELATIVE and mirror anime_tracker exactly.
"""
import os, io
import cairosvg
from PIL import Image, ImageDraw

CORAL = (232, 98, 74, 255)
NEARBLACK = (13, 11, 9, 255)
CORAL_HEX = "#E8624A"
NEARBLACK_HEX = "#0D0B09"

OUT = "/home/claude/hanj-brand-v2"
RES = "android/app/src/main/res"

WING_PATHS = [("M36 99 Q64 89 96 57", 9.0), ("M40 85 Q62 73 88 41", 6.5),
              ("M45 73 Q60 59 78 29", 4.5)]
TWO_STROKE = [("M34 102 Q62 92 90 60", 11.0), ("M39 82 Q60 68 82 38", 7.0)]
DENS = [("mdpi", 108), ("hdpi", 162), ("xhdpi", 216), ("xxhdpi", 324), ("xxxhdpi", 432)]
LEGACY = [("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)]
NOTIF = [("mdpi", 24), ("hdpi", 36), ("xhdpi", 48), ("xxhdpi", 72), ("xxxhdpi", 96)]


def wing_svg(paths, color, box=132):
    body = "".join(f'<path d="{d}" fill="none" stroke="{color}" stroke-width="{w}" '
                   f'stroke-linecap="round"/>' for d, w in paths)
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{box}" height="{box}" '
            f'viewBox="0 0 {box} {box}">{body}</svg>')


def render(svg, w, h):
    return Image.open(io.BytesIO(cairosvg.svg2png(
        bytestring=svg.encode(), output_width=w, output_height=h))).convert("RGBA")


def wing_tight(paths, color, size):
    big = render(wing_svg(paths, color), 2000, 2000)
    bb = big.crop(big.split()[3].getbbox())
    s = size / max(bb.size)
    return bb.resize((max(1, round(bb.width * s)), max(1, round(bb.height * s))), Image.LANCZOS)


def rounded_square(size, rf, color):
    ss = 4
    img = Image.new("RGBA", (size * ss, size * ss), (0, 0, 0, 0))
    ImageDraw.Draw(img).rounded_rectangle([0, 0, size * ss - 1, size * ss - 1],
                                          radius=int(size * ss * rf), fill=color)
    return img.resize((size, size), Image.LANCZOS)


def paste_center(base, layer):
    base.alpha_composite(layer, ((base.width - layer.width) // 2,
                                 (base.height - layer.height) // 2))
    return base


def disc_with_hole(canvas, disc_d, wing_frac=0.64):
    """Coral disc, wing punched as TRUE transparency so the background layer shows."""
    paths = WING_PATHS if canvas >= 96 else TWO_STROKE
    ss = 4
    db = int(disc_d * ss)
    disc = Image.new("RGBA", (db, db), (0, 0, 0, 0))
    ImageDraw.Draw(disc).ellipse([0, 0, db - 1, db - 1], fill=CORAL)
    w = wing_tight(paths, "#FFFFFF", int(db * wing_frac))
    hole = Image.new("L", (db, db), 0)
    hole.paste(w.split()[3], ((db - w.width) // 2, (db - w.height) // 2))
    a = disc.split()[3]
    disc.putalpha(Image.composite(Image.new("L", (db, db), 0), a, hole))
    return paste_center(Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0)),
                        disc.resize((disc_d, disc_d), Image.LANCZOS))


def full_icon(size, rf=0.22, disc_frac=0.62, bleed=False, circle=False):
    if circle:
        ss = 4
        base = Image.new("RGBA", (size * ss, size * ss), (0, 0, 0, 0))
        ImageDraw.Draw(base).ellipse([0, 0, size * ss - 1, size * ss - 1], fill=NEARBLACK)
        base = base.resize((size, size), Image.LANCZOS)
    elif bleed:
        base = Image.new("RGBA", (size, size), NEARBLACK)
    else:
        base = rounded_square(size, rf, NEARBLACK)
    base.alpha_composite(disc_with_hole(size, int(size * disc_frac)))
    return base


def save(img, name):
    p = os.path.join(OUT, name)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    img.save(p)
    return name


made = []

# --- vector masters -----------------------------------------------------
def master_svg(paths, color, label):
    big = render(wing_svg(paths, color), 1320, 1320)
    x0, y0, x1, y1 = [v / 10.0 for v in big.split()[3].getbbox()]
    pad = 4
    vb = f"{x0-pad:.2f} {y0-pad:.2f} {x1-x0+2*pad:.2f} {y1-y0+2*pad:.2f}"
    body = "".join(f'<path d="{d}" fill="none" stroke="{color}" stroke-width="{w}" '
                   f'stroke-linecap="round"/>' for d, w in paths)
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{vb}" role="img" '
            f'aria-label="Hanj">{body}</svg>'), (x0, y0, x1, y1)

for fn, paths, col in [("hanj_wing.svg", WING_PATHS, CORAL_HEX),
                       ("hanj_wing_mono.svg", WING_PATHS, "#FFFFFF"),
                       ("hanj_wing_two_stroke.svg", TWO_STROKE, CORAL_HEX),
                       ("hanj_wing_two_stroke_mono.svg", TWO_STROKE, "#FFFFFF")]:
    svg, _ = master_svg(paths, col, fn)
    os.makedirs(os.path.join(OUT, "assets/icon"), exist_ok=True)
    open(os.path.join(OUT, "assets/icon", fn), "w").write(svg)
    made.append(f"assets/icon/{fn}")

# favicon + inline shell snippet, both from the TWO-STROKE master
_, (tx0, ty0, tx1, ty1) = master_svg(TWO_STROKE, CORAL_HEX, "")
tbody = "".join(f'<path d="{d}" fill="none" stroke="{CORAL_HEX}" stroke-width="{w}" '
                f'stroke-linecap="round"/>' for d, w in TWO_STROKE)
sc = 0.62
grp = (f'<g transform="translate({32-(tx1-tx0)*sc/2:.2f},{32-(ty1-ty0)*sc/2:.2f}) '
       f'scale({sc}) translate({-tx0:.2f},{-ty0:.2f})">{tbody}</g>')
os.makedirs(os.path.join(OUT, "web"), exist_ok=True)
open(os.path.join(OUT, "web/favicon.svg"), "w").write(
    f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" role="img" '
    f'aria-label="Hanj"><rect width="64" height="64" rx="14" fill="{NEARBLACK_HEX}"/>'
    f'{grp}</svg>')
made.append("web/favicon.svg")
open(os.path.join(OUT, "LOADING-SHELL-SNIPPET.svg"), "w").write(
    f'<!-- for the #hanj-splash block in web/index.html: no background rect, the shell '
    f'already paints #0D0B09 -->\n'
    f'<svg width="64" height="64" viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg" '
    f'aria-hidden="true">{grp}</svg>\n')
made.append("LOADING-SHELL-SNIPPET.svg")

# --- adaptive foreground + NEW background layer -------------------------
for d, px in DENS:
    made.append(save(disc_with_hole(px, int(px * 0.60)),
                     f"{RES}/drawable-{d}/ic_launcher_foreground.png"))
    made.append(save(Image.new("RGBA", (px, px), NEARBLACK),
                     f"{RES}/drawable-{d}/ic_launcher_background.png"))
    # mipmap copies referenced by ic_launcher_round.xml — overwritten, not deleted
    made.append(save(disc_with_hole(px, int(px * 0.60)),
                     f"{RES}/mipmap-{d}/ic_launcher_foreground.png"))

# --- legacy + round launcher -------------------------------------------
for d, px in LEGACY:
    made.append(save(full_icon(px), f"{RES}/mipmap-{d}/ic_launcher.png"))
    made.append(save(full_icon(px, circle=True), f"{RES}/mipmap-{d}/ic_launcher_round.png"))

# --- notification small icon -------------------------------------------
for d, px in NOTIF:
    c = Image.new("RGBA", (px, px), (0, 0, 0, 0))
    made.append(save(paste_center(c, wing_tight(TWO_STROKE, "#FFFFFF", int(px * 0.82))),
                     f"{RES}/drawable-{d}/ic_notification.png"))

# --- PWA ----------------------------------------------------------------
for px in (192, 512):
    made.append(save(full_icon(px, rf=0.20), f"web/icons/Icon-{px}.png"))
    made.append(save(full_icon(px, disc_frac=0.46, bleed=True),
                     f"web/icons/Icon-maskable-{px}.png"))

# --- Flutter inline asset, CORRECT name ---------------------------------
for sub, m in [("", 1), ("2.0x/", 2), ("3.0x/", 3)]:
    px = 96 * m
    c = Image.new("RGBA", (px, px), (0, 0, 0, 0))
    made.append(save(paste_center(c, wing_tight(WING_PATHS, CORAL_HEX, int(px * 0.94))),
                     f"assets/images/{sub}hanj_wing_transparent.png"))

# --- masters + flutter_launcher_icons generator inputs ------------------
made.append(save(full_icon(1024, bleed=True), "assets/icon/app_icon_1024.png"))
made.append(save(disc_with_hole(1024, int(1024 * 0.60)),
                 "assets/icon/ic_launcher_foreground.png"))
made.append(save(Image.new("RGBA", (1024, 1024), NEARBLACK),
                 "assets/icon/ic_launcher_background.png"))

print(f"{len(made)} files")
for m in sorted(made):
    print(" ", m)
