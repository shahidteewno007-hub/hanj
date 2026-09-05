import os, io, cairosvg
from PIL import Image

OUT = "/home/claude/hanj-mono-addendum"
RES = "android/app/src/main/res"
WING = [("M36 99 Q64 89 96 57", 9.0), ("M40 85 Q62 73 88 41", 6.5), ("M45 73 Q60 59 78 29", 4.5)]

def wing_tight(size):
    body = "".join(f'<path d="{d}" fill="none" stroke="#FFFFFF" stroke-width="{w}" '
                   f'stroke-linecap="round"/>' for d, w in WING)
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" width="132" height="132" '
           f'viewBox="0 0 132 132">{body}</svg>')
    big = Image.open(io.BytesIO(cairosvg.svg2png(bytestring=svg.encode(),
          output_width=2000, output_height=2000))).convert("RGBA")
    bb = big.crop(big.split()[3].getbbox())
    s = size / max(bb.size)
    return bb.resize((max(1, round(bb.width*s)), max(1, round(bb.height*s))), Image.LANCZOS)

def save(img, name):
    p = os.path.join(OUT, name); os.makedirs(os.path.dirname(p), exist_ok=True)
    img.save(p); return name

made = []
# monochrome layer: the wing silhouette alone, not the knockout disc.
# The system tints this flat; a filled disc with holes reads as a blob when tinted.
for d, px in [("mdpi",108),("hdpi",162),("xhdpi",216),("xxhdpi",324),("xxxhdpi",432)]:
    c = Image.new("RGBA", (px, px), (0,0,0,0))
    w = wing_tight(int(px*0.55))
    c.alpha_composite(w, ((px-w.width)//2, (px-w.height)//2))
    made.append(save(c, f"{RES}/drawable-{d}/ic_launcher_monochrome.png"))
c = Image.new("RGBA", (1024,1024), (0,0,0,0))
w = wing_tight(int(1024*0.55))
c.alpha_composite(w, ((1024-w.width)//2, (1024-w.height)//2))
made.append(save(c, "assets/icon/ic_launcher_monochrome.png"))
print(len(made), "files"); [print(" ", m) for m in made]
