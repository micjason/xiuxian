#!/usr/bin/env python3
"""Reproducible irregular-grid cuts. Source is read-only; coordinates are source pixels.
An actual alpha sheet, NOT a green screen: trim alpha noise, never RGB-key cyan robes.
All hero frames share (240,280) foot anchor, 130px reference standing height.
"""
from pathlib import Path
import json
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter
from scipy import ndimage
ROOT=Path(__file__).resolve().parents[1]
source=Image.open(ROOT/'art/hero_sheet.png').convert('RGBA')
a=np.array(source)
alpha=a[:,:,3].astype(float)
a[:,:,3]=np.clip((alpha-10)*255/242,0,255).astype('uint8')
# Remove detached one-pixel keying debris, preserving intentional glow components.
labels,n=ndimage.label(a[:,:,3]>0)
sizes=np.bincount(labels.ravel());a[:,:,3][sizes[labels]<10]=0
# Explicit gold-banner exclusion, independent of the irregular cell boundaries.
for x0,y0,x1,y1 in [(0,0,105,30),(580,0,680,30),(0,180,110,207),
 (630,180,735,210),(1160,180,1255,208),(0,340,130,366),
 (700,340,840,369),(0,515,140,550),(1000,516,1100,552),
 (0,690,105,720),(660,690,795,720),(1040,690,1180,720),
 (0,865,175,895),(800,865,960,896)]: a[y0:y1,x0:x1,3]=0
clean=Image.fromarray(a)
# (crop left,top,right,bottom; foot x,y). Label rows are excluded explicitly.
spec={
 '移动': [(570,25,722,168,665,158),(722,25,850,168,791,158),(850,25,985,168,927,158),(985,25,1120,168,1066,159),(1120,25,1255,168,1201,160),(1255,25,1400,168,1339,160),(1400,25,1536,168,1468,159)],
 '奔跑':[(0,194,157,330,99,321),(157,194,286,330,230,321),(286,194,413,330,358,321),(413,194,615,330,535,321)],
 '冲刺':[(615,208,800,330,747,321),(800,208,960,330,893,321),(960,208,1160,330,1061,321)],
 '跳跃':[(1160,192,1320,330,1261,318),(1320,192,1410,330,1366,321),(1410,185,1536,330,1462,307)],
 '普通攻击':[(0,365,178,507,109,498),(178,365,298,507,235,496),(298,365,420,507,356,496),(420,365,532,507,476,497),(532,365,700,507,601,496)],
 '技能攻击':[(700,342,890,506,817,495),(890,342,1040,506,960,495),(1040,342,1240,506,1162,495),(1240,342,1536,506,1306,495)],
 '技能施放':[(0,550,167,688,102,674),(167,550,280,688,226,674),(280,522,405,688,339,674),(405,550,540,688,473,674),(540,522,690,688,607,674)],
 '受击':[(1000,560,1105,690,1051,682),(1105,560,1211,690,1159,681),(1211,560,1324,690,1261,681),(1324,560,1536,690,1386,676)],
 '倒地':[(0,712,156,854,95,801),(156,712,282,854,219,804),(282,712,417,854,346,804),(417,712,538,854,476,803),(538,710,646,854,589,842)],
 '胜利':[(660,723,800,855,744,845),(800,705,915,855,859,841),(915,705,1035,855,969,841)],
}
fx={
 '特效素材':[(1035,730,1192,863),(1192,710,1362,863),(1362,710,1536,863)],
 '技能特效-剑气':[(0,894,113,1014),(113,894,212,1014),(212,894,320,1014),(320,894,440,1014),(440,894,570,1014),(570,894,690,1014),(690,894,800,1014)],
 '技能特效-爆炸':[(800,896,946,1014),(946,892,1080,1014),(1080,892,1195,1014),(1195,892,1300,1014),(1300,892,1425,1014),(1425,892,1536,1014)],
}
manifest={'source_size':source.size,'source_alpha_range':[int(alpha.min()),int(alpha.max())], 'background':'Existing alpha; no green screen. Low-alpha debris removed; cyan/white preserved.', 'anchor':[240,280], 'canvas':[640,320], 'standing_height':130,'fps':11,'hero':{},'fx':{}}
allrows=[]
for name,cells in spec.items():
 out=ROOT/'frames/hero'/name;out.mkdir(parents=True,exist_ok=True)
 thumbs=[]
 for i,cell in enumerate(cells):
  x0,y0,x1,y1,footx,footy=cell
  sprite=clean.crop((x0,y0,x1,y1))
  # A label overlaps the top-left of the first skill cell, not the character.
  if name=='技能攻击' and i==0:
   ar=np.array(sprite);ar[:26,:145,3]=0;sprite=Image.fromarray(ar)
  # Fifth cast is the character, not the adjacent free-flying portal/bolt.
  if name=='技能施放' and i==4:
   ar=np.array(sprite);ar[:,:,-1][:,130:]=0;sprite=Image.fromarray(ar)
  # Cell-local components: a neighboring sleeve may enter the rectangle even
  # when its owning sprite is outside. Keep only the character-connected form.
  ar=np.array(sprite)
  if name=='技能攻击' and i==3:
   # Previous pose's giant crescent overlaps the left edge of this source cell.
   mask=Image.new('L',sprite.size,0)
   points=[(1290,342),(1536,342),(1536,506),(1258,506),(1254,492),
    (1261,480),(1265,458),(1261,447),(1267,428),(1273,410),
    (1280,395),(1270,388),(1280,375)]
   ImageDraw.Draw(mask).polygon([(x-x0,y-y0) for x,y in points],fill=255)
   mask=mask.filter(ImageFilter.GaussianBlur(2.0))
   ar[:,:,3]=(ar[:,:,3].astype(float)*np.array(mask)/255).astype('uint8')
  ll,nn=ndimage.label(ar[:,:,3]>20)
  counts=np.bincount(ll.ravel());counts[0]=0
  if counts.max()>0:
   main=ll==int(counts.argmax());support=ndimage.binary_dilation(main,iterations=2)
   ar[:,:,3][~support]=0
  sprite=Image.fromarray(ar)
  canvas=Image.new('RGBA',(640,320));canvas.alpha_composite(sprite,(240+x0-footx,280+y0-footy));canvas.save(out/f'{i:02}.png')
  thumb=Image.new('RGBA',(170,190),(32,42,50,255)); tight=canvas.crop((130,100,510,300));tight.thumbnail((166,155));thumb.alpha_composite(tight,((170-tight.width)//2,15));ImageDraw.Draw(thumb).text((8,170),f'{i:02}',fill='white');thumbs.append(thumb)
 manifest['hero'][name]={'count':len(cells),'cells':[list(c) for c in cells]};allrows.append((name,thumbs))
for name,cells in fx.items():
 out=ROOT/'frames/fx'/name;out.mkdir(parents=True,exist_ok=True);thumbs=[]
 for i,box in enumerate(cells):
  spr=clean.crop(box);canvas=Image.new('RGBA',(320,240));canvas.alpha_composite(spr,((320-spr.width)//2,210-spr.height));canvas.save(out/f'{i:02}.png')
  thumb=Image.new('RGBA',(170,190),(32,42,50,255));tight=canvas.copy();tight.thumbnail((166,155));thumb.alpha_composite(tight,((170-tight.width)//2,15));ImageDraw.Draw(thumb).text((8,170),f'{i:02}',fill='white');thumbs.append(thumb)
 manifest['fx'][name]={'count':len(cells),'cells':[list(c) for c in cells]};allrows.append((name,thumbs))
fontpath='/usr/share/fonts/truetype/droid/DroidSansFallbackFull.ttf'
if not Path(fontpath).exists():
 fontpath=next(iter(Path('/usr/share/fonts').rglob('*CJK*')),None)
font=ImageFont.truetype(str(fontpath),22) if fontpath else ImageFont.load_default()
sheet=Image.new('RGB',(1300,len(allrows)*200),(17,26,32));draw=ImageDraw.Draw(sheet)
for r,(name,thumbs) in enumerate(allrows):
 draw.text((10,r*200+65),name,font=font,fill=(205,233,244))
 for col,t in enumerate(thumbs):sheet.paste(t.convert('RGB'),(185+col*155,r*200))
(ROOT/'preview').mkdir(exist_ok=True);sheet.save(ROOT/'preview/sheet_slices_contact.png')
(ROOT/'frames/manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2))
print({k:len(v) for k,v in spec.items()});print({k:len(v) for k,v in fx.items()})
# Test source untouched, frame counts, transparent borders, and common canvas/anchor.
assert source.size==(1536,1024)
for category,groups,size in [('hero',spec,(640,320)),('fx',fx,(320,240))]:
 for name,cells in groups.items():
  paths=list((ROOT/'frames'/category/name).glob('*.png'));assert len(paths)==len(cells)
  for p in paths:
   im=Image.open(p);assert im.size==size and im.getbbox() is not None
   aa=np.array(im)[:,:,3];assert not aa[0].any() and not aa[-1].any(),p
aa=np.array(Image.open(ROOT/'frames/hero/普通攻击/02.png'))[:,:,3]
assert not aa[232:248,290:304].any(), 'neighbor sleeve regression'
aa=np.array(Image.open(ROOT/'frames/hero/技能攻击/03.png'))[:,:,3]
assert not aa[:,174:182].any(), 'foreign left crescent regression'
print('SLICE_TESTS PASS: counts/canvases/borders/foreign-fragment regressions')
