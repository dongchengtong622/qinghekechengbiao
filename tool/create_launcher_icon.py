"""Render the native calendar-and-leaf launcher design at Android densities."""
from pathlib import Path
from PIL import Image, ImageDraw
ROOT=Path(__file__).resolve().parent.parent
OUT=ROOT/'tool/android/icons'
OUT.mkdir(parents=True,exist_ok=True)
S=3
im=Image.new('RGBA',(512*S,512*S),'#D5F5E5'); d=ImageDraw.Draw(im)
def rect(box,fill,r=0):
 box=tuple(int(v*S) for v in box)
 d.rounded_rectangle(box,radius=int(r*S),fill=fill)
def bezier(points):
 out=[]
 for i in range(81):
  t=i/80; u=1-t
  out.append(tuple(S*(u*u*u*points[0][j]+3*u*u*t*points[1][j]+3*u*t*t*points[2][j]+t*t*t*points[3][j]) for j in (0,1)))
 return out
rect((99,140,415,424),'#B6DFCD',36)
rect((96,127,408,410),'#FCFFFD',34)
rect((96,127,408,212),'#FFFFFF',34)
rect((157,101,175,155),'#237457',9)
rect((317,101,335,155),'#237457',9)
for x,y,w,h,col in [(143,244,52,49,'#8ACCB0'),(214,244,52,49,'#DAEEE4'),(143,312,52,49,'#DAEEE4'),(214,312,52,49,'#8ACCB0'),(285,312,73,49,'#48A17E')]:
 rect((x,y,x+w,y+h),col,10)
leaf=bezier([(267,261),(252,160),(300,105),(405,94)])+bezier([(405,94),(411,190),(365,255),(267,261)])
d.polygon(leaf,fill='#247858')
vein=bezier([(265,274),(294,214),(334,170),(373,133)])
d.line(vein,fill='#D5F5E5',width=6*S,joint='curve')
for folder,size in [('mdpi',48),('hdpi',72),('xhdpi',96),('xxhdpi',144),('xxxhdpi',192)]:
 dest=OUT/f'mipmap-{folder}';dest.mkdir(parents=True,exist_ok=True)
 im.resize((size,size),Image.Resampling.LANCZOS).save(dest/'ic_launcher.png')
preview=ROOT/'assets/branding';preview.mkdir(parents=True,exist_ok=True)
im.resize((512,512),Image.Resampling.LANCZOS).save(preview/'icon_preview.png')
svg='<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512"><rect width="512" height="512" rx="108" fill="#D5F5E5"/><rect x="96" y="127" width="312" height="283" rx="34" fill="#FCFFFD"/><path d="M166 110v38 M326 110v38" stroke="#237457" stroke-width="18" stroke-linecap="round"/><g fill="#8ACCB0"><rect x="143" y="244" width="52" height="49" rx="10"/><rect x="214" y="312" width="52" height="49" rx="10"/></g><g fill="#DAEEE4"><rect x="214" y="244" width="52" height="49" rx="10"/><rect x="143" y="312" width="52" height="49" rx="10"/></g><rect x="285" y="312" width="73" height="49" rx="10" fill="#48A17E"/><path d="M267 261C252 160 300 105 405 94C411 190 365 255 267 261Z" fill="#247858"/><path d="M265 274C294 214 334 170 373 133" stroke="#D5F5E5" fill="none" stroke-width="6" stroke-linecap="round"/></svg>'
(preview/'icon.svg').write_text(svg,encoding='utf-8')
vector='<vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="108dp" android:height="108dp" android:viewportWidth="512" android:viewportHeight="512"><group android:scaleX="0.78" android:scaleY="0.78" android:translateX="56" android:translateY="56"><path android:fillColor="#FCFFFD" android:pathData="M130,127 L374,127 Q408,127 408,161 L408,376 Q408,410 374,410 L130,410 Q96,410 96,376 L96,161 Q96,127 130,127Z"/><path android:strokeColor="#237457" android:strokeWidth="18" android:strokeLineCap="round" android:pathData="M166,110L166,148M326,110L326,148"/><path android:fillColor="#8ACCB0" android:pathData="M143,244h52v49h-52ZM214,312h52v49h-52Z"/><path android:fillColor="#DAEEE4" android:pathData="M214,244h52v49h-52ZM143,312h52v49h-52Z"/><path android:fillColor="#48A17E" android:pathData="M285,312h73v49h-73Z"/><path android:fillColor="#247858" android:pathData="M267,261C252,160 300,105 405,94C411,190 365,255 267,261Z"/><path android:strokeColor="#D5F5E5" android:strokeWidth="6" android:strokeLineCap="round" android:pathData="M265,274C294,214 334,170 373,133"/></group></vector>'
(OUT/'drawable').mkdir(exist_ok=True)
(OUT/'drawable/ic_launcher_foreground.xml').write_text(vector,encoding='utf-8')
(OUT/'values').mkdir(exist_ok=True)
(OUT/'values/launcher_colors.xml').write_text('<resources><color name="ic_launcher_background">#D5F5E5</color></resources>',encoding='utf-8')
(OUT/'mipmap-anydpi-v26').mkdir(exist_ok=True)
(OUT/'mipmap-anydpi-v26/ic_launcher.xml').write_text('<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android"><background android:drawable="@color/ic_launcher_background"/><foreground android:drawable="@drawable/ic_launcher_foreground"/></adaptive-icon>',encoding='utf-8')
