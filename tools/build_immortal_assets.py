"""Build the immortal puppets from the currently selected reference artwork.

Dev-only: Python 3.13, Pillow, NumPy and the project's Godot 4.7.2.
SVG is the editable source; Godot rasterizes the same SVG into transparent PNG.
The atlas transform reuses build_fahai_assets.tile_piece's joint convention.
When the three new references are present, use direct cutout preparation.
The legacy vector redraw below is used only with an explicit --reference.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import shutil
import subprocess
import tempfile
from dataclasses import dataclass
from xml.sax.saxutils import escape

from PIL import Image, ImageDraw, ImageFont
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/puppets/immortals"
ART = ROOT / "docs/art/immortals"
GODOT = Path("D:/Godot/4.7.2/godot.exe")
TILE = 512
INK = "#302e22"
GOLD = "#b99a5e"
CREAM = "#d9d7b6"


def path(d, fill="none", stroke=INK, width=2.3, extra=""):
    return f'<path d="{d}" fill="{fill}" stroke="{stroke}" stroke-width="{width}" stroke-linecap="round" stroke-linejoin="round" {extra}/>'


def circle(x, y, r, fill, stroke="none", width=1):
    return f'<circle cx="{x}" cy="{y}" r="{r}" fill="{fill}" stroke="{stroke}" stroke-width="{width}"/>'


def ellipse(x, y, rx, ry, fill, stroke=INK, width=1.6):
    return f'<ellipse cx="{x}" cy="{y}" rx="{rx}" ry="{ry}" fill="{fill}" stroke="{stroke}" stroke-width="{width}"/>'


def cloud(x, y, scale=1, color=GOLD):
    d = "M-30 8 C-40 -2 -27 -12 -19 -7 C-19 -25 5 -23 4 -7 C21 -17 35 -2 23 8 C15 15 4 7 8 2 C14 -3 19 2 16 6 M-26 8 Q-1 24 26 8 M-17 18 Q0 29 17 18"
    return f'<g transform="translate({x} {y}) scale({scale})">{path(d, stroke=color, width=2)}</g>'


def medallion(x, y, r, base):
    bits = [circle(x, y, r, base, GOLD, 1.7), circle(x, y, r-4, "none", GOLD, 0.9)]
    for i in range(8):
        a = math.tau * i / 8
        dx, dy = x + math.cos(a)*r*.48, y + math.sin(a)*r*.48
        bits.append(f'<g transform="rotate({i*45} {dx} {dy})">{ellipse(dx,dy,3.1,r*.29,CREAM,GOLD,.7)}</g>')
    bits.extend([circle(x, y, 4.5, GOLD, INK, .7), circle(x,y,1.6,base)])
    return "".join(bits)


def surface(key, d, fill, bounds, *, pattern=True, gold=True):
    """Clipped engraved ornament with actual transparent pierced slots."""
    x0,y0,x1,y1 = bounds
    ornament, holes = [], []
    if pattern:
        row = 0
        for y in range(int(y0)+27, int(y1), 67):
            for x in range(int(x0)+20+(row%2)*31, int(x1)+30, 68):
                ornament.extend([medallion(x,y,21,"#88523c"),cloud(x+32,y+34,.37)])
            row += 1
        for y in range(int(y0)+18, int(y1)-7, 22):
            for x in (x0+9,x1-9):
                holes.append(f"M{x-1.7} {y-3} a1.7 3 0 1 0 3.4 0 a1.7 3 0 1 0 -3.4 0 Z")
    # Even-odd clipping pierces all layers, including the engraved decoration.
    cut = d + " " + " ".join(holes)
    # Intersect with the outer silhouette. An even-odd hole outside the panel
    # would otherwise become a detached filled island.
    clip = f'<defs><clipPath id="{key}-outer">{path(d,"white","none")}</clipPath><clipPath id="{key}-clip"><path d="{cut}" clip-rule="evenodd" fill-rule="evenodd"/></clipPath></defs>'
    result = clip + f'<g clip-path="url(#{key}-outer)"><g clip-path="url(#{key}-clip)">'
    result += path(d, fill)
    if gold:
        result += path(d, stroke=GOLD, width=8) + path(d, stroke=INK, width=2)
    result += "".join(ornament)
    # Quiet irregular pigment flecks, kept sparse so 1080p silhouettes stay clear.
    for j in range(42):
        x = x0 + ((j*47+13)%101)/101*(x1-x0)
        y = y0 + ((j*29+31)%103)/103*(y1-y0)
        result += circle(round(x,2),round(y,2),.8,"#dbc894")
    return result + "</g></g>"


def rivet(x,y):
    return circle(x,y,7,GOLD,INK,1.6)+circle(x-1.6,y-1.7,2.2,"#e2ca8e")+circle(x,y,1.4,INK)


@dataclass
class Part:
    name: str
    svg: str
    bounds: tuple
    pivot: tuple
    end: tuple | None = None
    parent: str = "root"
    reason: str = "清晰重绘；模糊纹样及遮挡连接处为补绘。"


def child_head(key, crane=False):
    pieces = []
    # Rear neck and the deeply cut side hair silhouette.
    pieces.append(path("M252 177 Q225 233 245 283 L218 351 Q267 356 298 330 L318 289 L317 177 Z","#263d31"))
    face = "M300 166 Q347 156 368 185 L373 213 L393 233 Q399 239 383 245 L386 256 Q397 261 382 267 L383 278 Q374 293 346 304 L303 291 L287 247 L290 205 Z"
    pieces.append(path(face,"#e6dfc8" if crane else "#b57860",width=2.8))
    pieces.append(path("M294 209 Q297 251 313 270 L318 290 L302 304 Q277 266 284 231 Z","#314136"))
    pieces.append(path("M317 205 Q339 182 363 202 M316 213 Q334 205 357 210",stroke=INK,width=5.5))
    pieces.append(path("M319 216 Q339 208 358 218 Q340 229 321 221 Z","#e9e3c8",width=1.4))
    pieces.extend([ellipse(345,217,3,5,INK,"none"),path("M366 210 Q359 229 374 238 M354 267 Q367 270 380 265",width=2.4)])
    pieces.append(path("M312 241 Q336 234 351 252 Q336 248 329 266 L318 266 Z","#455647" if crane else "#8b493d",width=1))
    pieces.append(path("M353 284 L337 292 L324 287",stroke="#554936",width=2))
    # Crown body, diagonally running beaded brow band and red finial.
    pieces.append(surface(key+"-crown","M226 142 Q218 115 237 94 L278 107 L306 118 L346 104 L361 124 L335 153 L263 204 L244 185 Z","#4c674c",(218,94,361,204),pattern=False))
    pieces.append(path("M230 132 Q240 110 273 120 L316 137 L271 179 Z","#839171",GOLD,2))
    pieces.extend([cloud(265,138,.42),path("M249 186 L355 116 L367 130 L262 204 Z","#d1c39c",INK,2)])
    for j in range(12):
        x,y=260+j*8,193-j*5.25
        pieces.append(circle(round(x,2),round(y,2),2.4,"#8a4b3a" if j%2 else "#42644e"))
    pieces.append(path("M353 115 L365 99",stroke=GOLD,width=5))
    pieces.extend([circle(368,93,11,"#a84d3e",INK,2),circle(364,89,3.8,"#d78d6f")])
    if crane:
        # Crown-mounted crane: rounded head, black eye, narrow beak, red crest.
        pieces.append(path("M229 122 Q212 103 219 82 Q211 59 228 46 Q249 31 264 47 Q276 56 271 71 L290 77 L269 83 Q252 79 251 69 Q237 70 240 94 L250 116 Z","#bec7aa",INK,2.5))
        pieces.append(path("M235 42 Q244 36 251 44 L246 52 L234 51 Z","#ad5444",INK,1))
        pieces.extend([circle(257,58,3.2,INK),path("M269 70 L291 77 L271 78 Z","#c2aa6c",INK,1),path("M226 96 Q241 98 242 110",width=2)])
    else:
        # Branches grow from the same crown so they remain structurally attached.
        pieces.append(path("M230 117 L215 90 L194 77 L177 81 L164 70 L154 48 L159 34 L167 62 L180 67 L174 39 L183 29 L186 60 L196 57 L202 35 L209 28 L209 65 L222 77 L226 54 L233 39 L234 79 L247 89 L254 106 Z","#7d8a59",INK,2.3))
        pieces.append(path("M207 100 L190 97 L178 111 L159 103 L154 88 L162 78 L165 94 L178 98 L186 86 L200 87 Z","#728257",INK,2))
        pieces.extend([ellipse(213,106,15,8,"#b3ad74"),circle(221,104,2,INK)])
    return "".join(pieces)


def old_head():
    bits = [path("M274 273 L340 296 L328 358 L267 345 Z","#b29a62",INK,2)]
    # High, bald forehead and the attached side-profile face: all face right.
    skull="M223 176 Q202 136 224 84 Q244 35 306 32 Q369 25 408 76 Q434 116 423 153 L414 187 L431 213 Q448 229 431 237 L426 244 L438 255 Q440 261 426 265 L430 278 Q419 304 384 313 L328 325 L270 287 L240 237 Z"
    bits.append(path(skull,"#c19a5b",INK,3))
    bits.append(path("M237 133 Q250 53 313 53 Q369 51 392 90 M258 77 Q304 52 349 71",stroke="#ddbc7d",width=3))
    bits.append(path("M324 180 Q371 170 409 183 M324 189 Q360 178 399 190",stroke="#aa8349",width=1.6))
    bits.append(path("M337 201 Q369 179 402 198 Q374 207 340 206 Z","#e7dfbf",INK,1.4))
    bits.append(path("M352 211 Q373 203 393 211 Q377 223 356 217 Z","#9b7b49",INK,2))
    bits.extend([ellipse(382,213,2.7,4.2,INK,"none"),path("M401 206 Q395 223 414 233 M393 257 L426 259",width=2)])
    # Soft white side hair, drawn as leather lobes, not photographic blur.
    bits.append(path("M237 166 Q218 153 215 177 Q188 168 191 193 Q174 204 193 216 Q181 244 206 242 Q202 267 226 259 Q232 284 256 266 L267 227 L260 188 Z","#c8ceac",INK,2))
    for i in range(6):
        bits.append(path(f"M{211+i*6} {178+i*5} Q{184+i*6} {200+i*5} {216+i*6} {231+i*4}",stroke="#879577",width=1.2))
    # Long divided moustache and beard belong to the head for nodding.
    beard="M342 249 Q367 253 390 269 Q418 270 431 285 Q446 340 431 397 Q423 457 392 528 L383 461 L369 520 L357 445 L340 500 Q316 440 311 377 L308 310 L322 273 Z"
    bits.append(path(beard,"#d5d8b7",INK,2.7))
    bits.append(path("M355 252 Q381 249 412 274 L442 306 Q420 311 398 289 L373 281 Q357 306 333 327 L321 318 Q337 286 342 268 Z","#ece6c8",INK,1.5))
    for i in range(13):
        x=327+i*7
        finish=462+(i%4)*14
        bits.append(path(f"M{x} 298 Q{x-5} 354 {x+5} 397 Q{x+9} 431 {x+6} {finish}",stroke="#8a987e",width=.9 if i%2 else 1.3))
    bits.extend([path("M353 327 Q344 391 358 449 M412 332 Q429 391 399 465",stroke="#f2eacd",width=3),circle(421,245,1.4,INK)])
    return "".join(bits)


def hand_svg(x,y):
    d=f"M{x-12} {y+5} L{x-7} {y-9} Q{x+6} {y-14} {x+13} {y-8} L{x+32} {y-12} Q{x+38} {y-9} {x+32} {y-5} L{x+17} {y-1} L{x+38} {y-1} Q{x+42} {y+3} {x+35} {y+5} L{x+18} {y+6} Q{x+9} {y+18} {x-4} {y+15} Z"
    return path(d,"#c7b68b",INK,2)+path(f"M{x+4} {y-2} Q{x+9} {y+5} {x+18} {y+6}",width=1.2)+rivet(x,y)


def make_character(key, title, *, elder=False, crane=False):
    robe = "#a38b44" if elder else ("#394b3e" if crane else "#3c4f3b")
    sleeve = "#6d713d" if elder else "#394438"
    parts=[]
    def add(name, svg, bounds, pivot, end=None, parent="root", reason=None):
        part=Part(name,svg,bounds,pivot,end,parent)
        if reason:
            part.reason=reason
        parts.append(part)
    add("head",old_head() if elder else child_head(key,crane),
        (175,25,449,531) if elder else (149,27,401,352),(294,335),parent="torso",
        reason="保留高额、长白须。" if elder else "保留参考头冠及脸色；冠饰细部为重绘。")
    torso="M244 321 Q266 307 296 329 L322 342 Q345 372 347 410 L333 491 L339 586 L358 661 Q281 696 202 666 L215 586 L218 477 L207 394 Q214 346 244 321 Z"
    deco=surface(key+"-torso",torso,robe,(202,310,358,695))
    deco+=path("M244 324 L263 326 L316 449 L298 504 L277 443 L228 344 Z","#c1c0a1",INK,2)
    deco+=path("M254 335 L308 450",stroke="#8a845b",width=2)
    deco+=path("M214 586 Q287 611 341 591 L346 620 Q279 640 207 613 Z","#94634a" if elder else "#7d4440",GOLD,2)
    deco+=cloud(278,610,.55,"#dbc38a")
    add("torso",deco,(200,307,359,696),(275,352),(276,644))
    # Both limbs overlap at the socket. Rear/front layers keep the side profile.
    arm_specs=[
        ("left_upper_arm","M237 347 Q269 332 281 376 L299 444 L301 487 L264 508 L238 464 L220 402 Z",(218,333,303,510),(251,370),(282,480),"torso"),
        ("left_forearm","M263 462 Q289 448 311 457 L368 435 L404 424 L419 461 L392 492 L345 509 L282 549 L249 523 Z",(247,423,421,551),(282,480),(405,446),"left_upper_arm"),
        ("right_upper_arm","M298 344 Q331 340 341 376 L368 450 L369 485 L339 507 L307 469 L292 411 Z",(290,339,372,509),(316,370),(350,480),"torso"),
        ("right_forearm","M328 464 Q348 446 373 452 L401 437 L433 428 L448 465 L420 484 L404 527 L368 554 L333 525 L317 492 Z",(315,426,450,556),(350,480),(436,448),"right_upper_arm")
    ]
    for name,d,bounds,pivot,end,parent in arm_specs:
        art=surface(key+"-"+name,d,sleeve,bounds,pattern=name.endswith("forearm"))
        art+=rivet(*pivot)
        if name.endswith("forearm"):
            wx,wy=end
            art+=path(f"M{wx-17} {wy-17} L{wx+3} {wy-20} L{wx+14} {wy+18} L{wx-9} {wy+22} Z",CREAM,INK,2)
        add(name,art,bounds,pivot,end,parent)
    add("left_hand",hand_svg(405,446),(391,430,450,465),(405,446),(436,446),"left_forearm")
    add("right_hand",hand_svg(436,448),(422,433,480,467),(436,448),(467,448),"right_forearm")
    legs=[
        ("left_thigh","M217 623 Q274 610 312 651 L320 727 L308 826 L203 844 L163 815 L190 732 Z",(161,610,322,846),(235,650),(225,807),"root"),
        ("left_calf","M179 787 L309 790 L321 842 L313 930 L302 975 Q224 992 135 958 Q125 940 137 920 L152 865 Z",(123,785,323,993),(225,807),(199,964),"left_thigh"),
        ("right_thigh","M265 622 Q321 617 352 657 L361 735 L389 810 L365 835 L256 832 L251 760 L254 683 Z",(249,617,391,837),(300,650),(348,812),"root"),
        ("right_calf","M260 789 L374 791 L395 850 L411 921 L422 953 L416 982 Q334 997 239 968 L246 917 L250 859 Z",(237,787,424,998),(348,812),(380,970),"right_thigh")
    ]
    for name,d,bounds,pivot,end,parent in legs:
        leg=surface(key+"-"+name,d,robe,bounds)
        if name.endswith("calf"):
            x,y=end
            boot=f"M{x-37} {y-20} Q{x-12} {y-9} {x+6} {y-16} L{x+24} {y-9} L{x+36} {y+7} L{x+34} {y+16} L{x-42} {y+15} Z"
            leg+=path(boot,"#333c30",GOLD,2)+path(f"M{x-37} {y+9} L{x+28} {y+9}",stroke=CREAM,width=1.2)
        leg+=rivet(*pivot)
        add(name,leg,bounds,pivot,end,parent)
    if elder:
        staff=path("M449 952 L455 459 Q455 419 440 416 Q427 415 428 435 Q429 445 438 442",stroke="#403c29",width=7)
        staff+=path("M454 480 L453 700",stroke="#a39763",width=1.3)+path("M448 458 L459 458 M448 466 L459 466",stroke=GOLD,width=3)
        add("staff",staff,(423,411,461,957),(452,450),parent="right_hand",reason="参考图可见拄杖；杖头及握持结构补绘。")
    else:
        ribbon=path("M242 162 L254 181 Q215 250 216 278 Q184 335 104 388 L83 387 Q151 308 174 250 L214 187 Z","#324b39",INK,2)
        ribbon+=path("M232 190 Q201 262 172 297 Q144 335 108 365 L141 319 Q185 252 210 206 Z","#b2b59a",INK,1.2)
        ribbon+=path("M243 175 Q217 231 207 277",stroke=GOLD,width=2)
        add("ribbons",ribbon,(81,160,255,390),(242,177),parent="head",reason="保留头冠后方长飘带；遮挡边缘补绘。")
    return {"key":key,"title":title,"parts":parts,"reference_facing":1,
            "skin_id":{"xianweng":4,"bailu":5,"baihe":6}[key]}


def svg_document(body, width, height, *, viewbox=None):
    viewbox=viewbox or f"0 0 {width} {height}"
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="{viewbox}">{body}</svg>'


def atlas_transform(part):
    """Same normalization as Fahai: axial pieces point down; free pieces center."""
    start,end=part.pivot,part.end
    angle=math.pi/2-math.atan2(end[1]-start[1],end[0]-start[0]) if end else 0
    c,s=math.cos(angle),math.sin(angle)
    pivot=(256,100) if end else (256,256)
    x0,y0,x1,y1=part.bounds
    points=[(c*(x-start[0])-s*(y-start[1]),s*(x-start[0])+c*(y-start[1]))
            for x,y in [(x0,y0),(x0,y1),(x1,y0),(x1,y1)]]
    ratios=[]
    for x,y in points:
        if abs(x)>1e-6:
            ratios.append(((TILE-14-pivot[0]) if x>0 else (pivot[0]-14))/abs(x))
        if abs(y)>1e-6:
            ratios.append(((TILE-14-pivot[1]) if y>0 else (pivot[1]-14))/abs(y))
    length=math.dist(start,end) if end else 1
    scale=min(ratios+([320/length] if end else []))
    # Free-piece axis length records scale, although existing renderers ignore it.
    return angle,scale,pivot,scale*length if end else 1


def assembled(character, prefix="", interactive=False):
    by_name={p.name:p.svg for p in character["parts"]}
    def piece(name):
        return f'<g data-piece="{name}">{by_name[name]}</g>'
    def joint(name,x,y,body):
        return f'<g id="{prefix}{name}" data-joint="{name}" data-pivot="{x},{y}" transform="rotate(0 {x} {y})">{body}</g>'
    rear_leg=joint("left_hip",235,650,piece("left_thigh")+joint("left_knee",225,807,piece("left_calf")))
    front_leg=joint("right_hip",300,650,piece("right_thigh")+joint("right_knee",348,812,piece("right_calf")))
    rear_arm=joint("left_arm",251,370,piece("left_upper_arm")+joint("left_elbow",282,480,piece("left_forearm")+piece("left_hand")))
    staff=piece("staff") if "staff" in by_name else ""
    front_arm=joint("right_arm",316,370,piece("right_upper_arm")+joint("right_elbow",350,480,piece("right_forearm")+staff+piece("right_hand")))
    ribbon=piece("ribbons") if "ribbons" in by_name else ""
    head=joint("head",294,335,ribbon+piece("head"))
    upper=joint("waist",276,644,rear_arm+piece("torso")+front_arm+head)
    return f'<g id="{prefix}figure">{rear_leg}{front_leg}{upper}</g>'


def write_art(characters,reference):
    OUT.mkdir(parents=True,exist_ok=True)
    ART.mkdir(parents=True,exist_ok=True)
    source_dir=OUT/"source"
    source_dir.mkdir(exist_ok=True)
    (source_dir/".gdignore").write_text("",encoding="utf-8")
    (ART/".gdignore").write_text("",encoding="utf-8")
    source=source_dir/"reference.png"
    if reference:
        shutil.copyfile(reference,source)
    if not source.is_file():
        raise FileNotFoundError("Use --reference to retain the approved image.")
    manifest={
        "version":1,"atlas_size":[2048,2048],"tile_size":[512,512],
        "part_coordinate_space":"reference_axis/reference_bounds 均为重绘稿 560×1010 坐标，不是原始截图坐标。",
        "reference":{"filename":"source/reference.png","size":list(Image.open(source).size),
                     "sha256":hashlib.sha256(source.read_bytes()).hexdigest(),
                     "method":"用户确认的清晰矢量重绘；服装与冠饰细节并非从低清图精确提取。",
                     "back":"未提供独立反面；预览整体镜像。",
                     "alpha":"孔洞为真实透明；皮革透光由使用端材质处理，非实测值。"},
        "characters":{}
    }
    jobs=[]
    for char in characters:
        body=[]
        parts={}
        for index,p in enumerate(char["parts"]):
            angle,scale,pivot,axis=atlas_transform(p)
            x,y=index%4*TILE,index//4*TILE
            transform=f"translate({x+pivot[0]} {y+pivot[1]}) scale({scale:.8f}) rotate({math.degrees(angle):.8f}) translate({-p.pivot[0]} {-p.pivot[1]})"
            body.append(f'<g id="{p.name}" transform="{transform}">{p.svg}</g>')
            parts[p.name]={"rect":[x,y,512,512],"pivot":list(pivot),"axis_pixels":axis,
                           "opacity":1.0,"inferred":True,"reconstruction":p.reason,
                           "parent":p.parent,"reference_axis":[list(p.pivot)]+([list(p.end)] if p.end else []),
                           "reference_bounds":list(p.bounds)}
        atlas=OUT/(char["key"]+".svg")
        atlas.write_text(svg_document("".join(body),2048,2048),encoding="utf-8")
        jobs.append(atlas)
        pose=ART/(char["key"]+"-pose.svg")
        pose.write_text(svg_document(assembled(char),560,1010),encoding="utf-8")
        jobs.append(pose)
        manifest["characters"][char["key"]]={
            "name_zh":char["title"],"skin_id":char["skin_id"],"reference_facing":1,
            "atlas":char["key"]+".png","editable":char["key"]+".svg",
            "head_size_per_radius":5.0 if char["key"]=="xianweng" else 3.75,
            "hand_size_ratio":.17,"shoulder_half_width_ratio":.075,
            "joint_hex":GOLD,"ink_hex":INK,"parts":parts,
            "layout":{"canvas_size":[560,1010],"waist":[276,644],
                      "left_shoulder":[251,370],"left_elbow":[282,480],"left_wrist":[405,446],
                      "right_shoulder":[316,370],"right_elbow":[350,480],"right_wrist":[436,448],
                      "head_pivot":[294,335]},
            "accessories":{"staff":{"parent":"right_hand","grip":[452,450]}} if char["key"]=="xianweng" else {"ribbons":{"parent":"head"}},
            "registration":"资产准备完成；尚未注册到游戏人物显示端。"
        }
    (OUT/"immortals-assets.json").write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    return jobs,manifest


def rasterize(jobs,godot):
    if not godot.is_file():
        raise FileNotFoundError(f"Godot executable not found: {godot}")
    result=subprocess.run([str(godot),"--version"],capture_output=True,text=True,check=True)
    if result.stdout.strip()!="4.7.2.stable.official.ed1daf0bf":
        raise RuntimeError("Project Godot version mismatch: "+result.stdout.strip())
    script='''extends SceneTree
func _initialize() -> void:
    for filename: String in OS.get_cmdline_user_args():
        var svg := FileAccess.get_file_as_string(filename)
        var texture := Image.new()
        var err := texture.load_svg_from_string(svg)
        if err != OK:
            push_error("SVG rasterization failed: %s (%s)" % [filename, err])
            quit(1)
            return
        var destination := filename.get_basename() + ".png"
        err = texture.save_png(destination)
        if err != OK:
            push_error("PNG save failed: %s (%s)" % [destination, err])
            quit(1)
            return
        print("RASTERIZED: ", destination)
    quit(0)
'''
    with tempfile.TemporaryDirectory(prefix="dengxia-immortals-") as tmp:
        entry=Path(tmp)/"rasterize.gd"
        entry.write_text(script,encoding="utf-8")
        subprocess.run([str(godot),"--headless","--path",str(ROOT),"--check-only","--script",str(entry)],check=True)
        subprocess.run([str(godot),"--headless","--path",str(ROOT),"--script",str(entry),"--",*[str(p) for p in jobs]],check=True)


def verify(manifest):
    report=[]
    for key,char in manifest["characters"].items():
        img=Image.open(OUT/char["atlas"]).convert("RGBA")
        if img.size!=(2048,2048):
            raise ValueError(f"{key}: wrong atlas dimensions")
        alpha=np.asarray(img)[:,:,3]
        if not (np.any(alpha==0) and np.any(alpha==255)):
            raise ValueError(f"{key}: transparent background or opaque leather missing")
        for name,part in char["parts"].items():
            x,y,w,h=part["rect"]
            tile=alpha[y:y+h,x:x+w]
            if np.count_nonzero(tile)<100:
                raise ValueError(f"{key}/{name}: empty cutout")
            edge=np.concatenate((tile[:4].ravel(),tile[-4:].ravel(),tile[:,:4].ravel(),tile[:,-4:].ravel()))
            if np.any(edge>0):
                raise ValueError(f"{key}/{name}: cutout clipped at tile edge")
            px,py=part["pivot"]
            # Head and loose ribbons use a neck/attachment pivot, not their bbox centre.
            if name not in ("head","ribbons") and not np.any(tile[py-8:py+9,px-8:px+9]>0):
                raise ValueError(f"{key}/{name}: attachment pivot outside the leather")
        report.append({"character":key,"parts":len(char["parts"]),"size":list(img.size),
                       "transparent_pixels":int(np.count_nonzero(alpha==0)),"tile_edges":"clear"})
    (ART/"asset-checks.json").write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print("ASSET_CHECKS:",json.dumps(report,ensure_ascii=False))


def preview(characters):
    template=(ROOT/"tools/immortal_preview.html").read_text(encoding="utf-8")
    figures=[]
    # Keep the reference left-to-right order.
    for index,key in enumerate(("bailu","baihe","xianweng")):
        char=next(c for c in characters if c["key"]==key)
        drawing=svg_document(assembled(char,key+"-",True),560,1010)
        figures.append(f'<div class="actor" data-character="{key}"><div class="actor-label"><span>0{index+1}</span><strong>{escape(char["title"])}</strong></div><div class="flip">{drawing}</div></div>')
    page=template.replace("{{FIGURES}}","".join(figures))
    (ART/"preview.html").write_text(page,encoding="utf-8")


def presentation_board():
    board=Image.new("RGB",(1800,1200),"#e9e2cf")
    draw=ImageDraw.Draw(board)
    font_path=Path("C:/Windows/Fonts/simsun.ttc")
    if not font_path.is_file():
        raise FileNotFoundError("Chinese presentation font not found: "+str(font_path))
    title=ImageFont.truetype(str(font_path),42)
    label=ImageFont.truetype(str(font_path),28)
    small=ImageFont.truetype(str(font_path),17)
    draw.text((68,40),"灯下 · 昆仑三仙",font=title,fill="#373d30")
    draw.text((69,99),"鹿童 / 鹤童 / 南极仙翁",font=small,fill="#877759")
    for index,(key,name) in enumerate((("bailu","白鹿 · 鹿童"),("baihe","白鹤 · 鹤童"),("xianweng","仙翁"))):
        pose=Image.open(ART/(key+"-pose.png")).convert("RGBA")
        pose.thumbnail((530,960),Image.Resampling.LANCZOS)
        x=48+index*580+(530-pose.width)//2
        board.paste(pose,(x,156),pose)
        draw.text((x+pose.width//2,1157),name,font=label,fill="#625b43",anchor="mm")
    draw.line((58,1128,1742,1128),fill="#b8a783",width=1)
    board.save(ART/"lineup.png",optimize=True)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reference",type=Path)
    parser.add_argument("--godot",type=Path,default=GODOT)
    args=parser.parse_args()
    if not args.reference and all((OUT/"source"/(key+"-reference.png")).is_file()
                                  for key in ("xianweng","bailu","baihe")):
        from prepare_immortal_reference_assets import build
        build({})
        return
    characters=[make_character("xianweng","仙翁",elder=True),
                make_character("bailu","白鹿 · 鹿童"),make_character("baihe","白鹤 · 鹤童",crane=True)]
    jobs,manifest=write_art(characters,args.reference)
    preview(characters)
    rasterize(jobs,args.godot)
    verify(manifest)
    presentation_board()


if __name__=="__main__":
    main()
