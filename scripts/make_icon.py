"""Render Importone's geometric bell/import mark from code (Pillow)."""
from PIL import Image, ImageDraw
from pathlib import Path
out=Path(__file__).resolve().parents[1]/'Preferences/Resources'
n=1024
im=Image.new('RGB',(n,n)); px=im.load()
for y in range(n):
    for x in range(n):
        t=(x+y)/(2*n); px[x,y]=(int(125-69*t),int(85+15*t),int(236-20*t))
d=ImageDraw.Draw(im)
d.rounded_rectangle((476,185,548,280),36,fill='white')
d.pieslice((280,245,744,705),180,360,fill='white')
d.polygon([(282,466),(742,466),(758,661),(805,729),(219,729),(266,661)],fill='white')
d.ellipse((453,744,571,856),fill='white')
d.rounded_rectangle((654,264,894,504),65,fill=(41,34,96))
d.line([(774,310),(774,416)],fill='white',width=24)
d.line([(730,378),(774,424),(818,378)],fill='white',width=24)
for scale in (1,2,3): im.resize((64*scale,64*scale),Image.Resampling.LANCZOS).save(out/('icon.png' if scale==1 else f'icon@{scale}x.png'))
im.save(out/'logo.png')
