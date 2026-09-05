import os, io, cairosvg
from PIL import Image
OUT="/home/claude/hanj-wing-text"
# "C" — the text/small optical cut. Opened gaps, heavier strokes, shorter third
# stroke so the fan survives down to 18px. Display cut (icons) is unchanged.
TEXT=[("M32 104 Q62 94 94 58",11.0),("M38 84 Q58 72 80 44",7.5),("M46 66 Q57 57 70 38",5.0)]
def tight(px,color="#E8624A"):
    body="".join(f'<path d="{d}" fill="none" stroke="{color}" stroke-width="{w}" stroke-linecap="round"/>' for d,w in TEXT)
    svg=f'<svg xmlns="http://www.w3.org/2000/svg" width="132" height="132" viewBox="0 0 132 132">{body}</svg>'
    big=Image.open(io.BytesIO(cairosvg.svg2png(bytestring=svg.encode(),output_width=2000,output_height=2000))).convert("RGBA")
    bb=big.crop(big.split()[3].getbbox()); s=px/max(bb.size)
    return bb.resize((max(1,round(bb.width*s)),max(1,round(bb.height*s))),Image.LANCZOS)
def save(img,name):
    p=os.path.join(OUT,name); os.makedirs(os.path.dirname(p),exist_ok=True); img.save(p); return name
made=[]
for sub,m in [("",1),("2.0x/",2),("3.0x/",3)]:
    px=96*m; c=Image.new("RGBA",(px,px),(0,0,0,0)); w=tight(int(px*0.94))
    c.alpha_composite(w,((px-w.width)//2,(px-w.height)//2))
    made.append(save(c,f"assets/images/{sub}hanj_wing_transparent.png"))
# vector masters for the text cut
big=Image.open(io.BytesIO(cairosvg.svg2png(bytestring=(
 '<svg xmlns="http://www.w3.org/2000/svg" width="132" height="132" viewBox="0 0 132 132">'+
 "".join(f'<path d="{d}" fill="none" stroke="#E8624A" stroke-width="{w}" stroke-linecap="round"/>' for d,w in TEXT)+
 '</svg>').encode(),output_width=1320,output_height=1320))).convert("RGBA")
x0,y0,x1,y1=[v/10.0 for v in big.split()[3].getbbox()]; pad=4
vb=f"{x0-pad:.2f} {y0-pad:.2f} {x1-x0+2*pad:.2f} {y1-y0+2*pad:.2f}"
for fn,col in [("hanj_wing_text.svg","#E8624A"),("hanj_wing_text_mono.svg","#FFFFFF")]:
    body="".join(f'<path d="{d}" fill="none" stroke="{col}" stroke-width="{w}" stroke-linecap="round"/>' for d,w in TEXT)
    os.makedirs(os.path.join(OUT,"assets/icon"),exist_ok=True)
    open(os.path.join(OUT,"assets/icon",fn),"w").write(
      f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{vb}" role="img" aria-label="Hanj">{body}</svg>')
    made.append(f"assets/icon/{fn}")
print(len(made),"files"); [print(" ",m,os.path.getsize(os.path.join(OUT,m)),"B") for m in made]
