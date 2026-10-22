"""Trace the two user-created reference photographs into existing puppet rigs.

Contours use the original 1280x2278 photo coordinates. No colour key is used:
ivory fabric and gold carving stay visible. Hidden garment is not redrawn.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import math
from pathlib import Path
import shutil

import numpy as np
from PIL import Image, ImageDraw, ImageFont

from prepare_fahai_photo import mask_for


# Polygon, proximal joint, distal joint. A small overlap joins adjacent pieces.
BAI = {
    "head": ([(615,451),(633,447),(644,456),(647,472),(662,459),(680,466),(685,484),
        (703,477),(716,491),(713,512),(731,520),(735,540),(722,550),(734,563),
        (729,588),(717,599),(710,624),(711,644),(714,664),(710,685),(716,704),
        (723,722),(719,727),(711,727),(713,739),(708,746),(710,754),(699,764),
        (681,766),(666,756),(651,745),(639,744),(626,771),(604,769),(603,741),
        (593,724),(578,713),(565,705),(552,700),(539,695),(530,685),(532,674),
        (513,670),(504,658),(502,641),(479,641),(459,649),(445,664),(420,678),
        (400,676),(379,661),(359,640),(343,616),(338,607),(353,615),(366,640),
        (391,657),(408,662),(432,651),(451,630),(485,616),(493,606),(480,591),
        (478,575),(486,563),(503,556),(527,556),(544,562),(533,545),(514,533),
        (510,518),(520,505),(535,502),(559,509),(578,520),(584,506),(574,492),
        (578,480),(593,474),(609,480),(612,490),(614,475),(605,466)], (642,660), None),
    "ribbons": ([(557,707),(579,711),(591,726),(581,773),(561,823),(538,878),
        (510,945),(486,1006),(460,1077),(436,1151),(414,1230),(397,1295),
        (376,1357),(353,1397),(330,1420),(346,1363),(361,1298),(387,1214),
        (413,1147),(438,1087),(461,1021),(485,953),(507,881),(531,797)], (565,725), None),
    "torso": ([(560,777),(588,776),(625,798),(647,829),(665,869),(680,928),
        (692,991),(701,1059),(709,1123),(730,1190),(750,1268),(504,1275),
        (509,1220),(521,1157),(530,1094),(527,1049),(521,1005),(513,958),
        (511,914),(516,873),(531,829)], (592,856), (600,1250)),
    "left_upper_arm": ([(528,846),(552,858),(554,897),(532,936),(504,974),
        (474,1016),(445,1051),(422,1045),(404,1025),(404,1002),(429,958),
        (459,912),(492,869)], (527,871), (449,1007)),
    "left_forearm": ([(425,995),(456,1001),(476,1035),(466,1081),(439,1127),
        (410,1171),(370,1211),(333,1239),(300,1260),(282,1214),(271,1163),
        (261,1114),(253,1067),(281,1050),(317,1044),(359,1033),(399,1018)],
        (443,1016), (284,1060)),
    "left_hand": ([(283,1041),(289,1066),(273,1073),(251,1078),(229,1080),
        (210,1081),(214,1075),(232,1066),(216,1068),(207,1072),(212,1064),
        (234,1055),(252,1051),(264,1055),(272,1046)], (280,1061), (224,1067)),
    "right_upper_arm": ([(635,851),(660,879),(682,913),(706,945),(735,969),
        (763,993),(770,1022),(753,1045),(727,1046),(704,1028),(681,1000),
        (660,970),(644,935),(631,902)], (647,876), (746,1012)),
    "right_forearm": ([(733,984),(759,987),(800,977),(843,961),(883,947),
        (902,944),(912,963),(920,994),(930,1035),(939,1078),(945,1121),
        (948,1166),(946,1207),(928,1208),(901,1200),(865,1185),(830,1164),
        (797,1141),(772,1108),(750,1070),(738,1034)], (749,1017), (901,960)),
    "right_hand": ([(899,944),(916,936),(926,927),(938,925),(945,929),
        (940,935),(925,941),(943,938),(952,939),(944,944),(928,950),
        (947,946),(953,950),(941,955),(926,958),(936,958),(945,957),
        (942,964),(923,970),(909,975)], (906,959), (941,944)),
    "lower_body": ([(510,1225),(733,1220),(767,1284),(790,1333),(812,1387),
        (836,1448),(864,1508),(900,1564),(941,1602),(987,1635),(1039,1667),
        (1099,1700),(1109,1709),(1086,1738),(1044,1764),(1006,1789),
        (961,1811),(923,1824),(896,1818),(877,1797),(858,1771),(838,1754),
        (822,1758),(795,1776),(752,1795),(710,1810),(666,1820),(636,1827),
        (619,1847),(579,1850),(555,1844),(556,1830),(518,1821),(478,1812),
        (463,1844),(432,1846),(398,1841),(386,1835),(400,1814),(357,1801),
        (343,1790),(362,1760),(382,1728),(404,1691),(426,1646),(450,1594),
        (468,1539),(482,1484),(493,1423),(502,1367)], (600,1250), None),
}

XU = {
    "head": ([(504,459),(526,445),(552,446),(575,448),(597,460),(615,479),
        (631,502),(638,521),(656,533),(678,556),(684,580),(679,599),(688,610),
        (692,632),(690,652),(686,671),(690,686),(696,701),(694,710),
        (685,711),(688,720),(681,728),(680,742),(667,748),(645,745),
        (627,735),(613,730),(597,747),(572,743),(572,720),(558,711),
        (547,696),(533,684),(527,666),(528,646),(523,644),(507,656),
        (483,670),(459,683),(433,697),(411,705),(395,699),(384,687),
        (385,680),(397,682),(410,689),(432,684),(455,670),(480,654),
        (505,638),(517,620),(506,608),(490,602),(480,589),(480,573),
        (488,551),(493,521),(501,490)], (598,630), None),
    "torso": ([(567,719),(596,725),(615,742),(627,766),(634,797),
        (635,835),(631,890),(631,947),(638,997),(646,1058),(651,1116),
        (657,1174),(668,1267),(441,1272),(447,1205),(461,1130),(469,1064),
        (480,1001),(490,940),(496,882),(510,834),(526,787),(551,751)],
        (567,812), (560,1250)),
    "left_upper_arm": ([(497,801),(526,809),(535,839),(516,881),(485,923),
        (451,963),(410,1000),(365,1046),(332,1070),(301,1046),(281,1023),
        (312,987),(351,952),(393,910),(436,867),(467,830)], (510,826), (332,1038)),
    "left_forearm": ([(296,1013),(337,1037),(357,1065),(348,1111),
        (332,1152),(315,1194),(303,1238),(292,1254),(250,1227),
        (209,1205),(170,1182),(131,1155),(125,1146),(158,1116),
        (196,1081),(242,1046)], (318,1040), (212,1213)),
    "left_hand": ([(203,1191),(237,1211),(237,1223),(219,1230),
        (203,1241),(191,1245),(194,1236),(211,1224),(192,1232),
        (181,1234),(183,1227),(204,1217),(185,1222),(179,1219),
        (187,1214),(208,1207)], (220,1210), (188,1234)),
    "right_upper_arm": ([(609,817),(627,846),(644,879),(665,910),(690,937),
        (712,959),(731,988),(727,1021),(706,1040),(684,1034),
        (658,1010),(640,978),(625,940),(612,901),(604,862)], (620,845), (701,1006)),
    "right_forearm": ([(673,960),(699,951),(733,938),(768,924),(788,919),
        (798,944),(809,975),(819,1008),(830,1042),(838,1076),
        (847,1112),(850,1132),(833,1137),(801,1133),(766,1126),
        (733,1111),(703,1090),(678,1061),(662,1030),(659,994)],
        (692,1011), (796,929)),
    "right_hand": ([(790,918),(808,909),(831,898),(854,891),
        (879,888),(892,890),(886,894),(859,898),(885,897),(894,900),
        (887,903),(861,905),(876,907),(884,911),(878,914),(859,912),
        (848,915),(866,917),(870,920),(864,924),(843,920),(827,926),
        (812,932),(797,937)], (801,924), (868,902)),
    "lower_body": ([(448,1225),(658,1224),(680,1299),(702,1370),
        (730,1450),(757,1520),(794,1594),(830,1667),(858,1734),
        (839,1745),(812,1760),(785,1774),(759,1790),(778,1792),
        (775,1810),(758,1828),(742,1843),(705,1847),(667,1848),
        (650,1838),(653,1828),(615,1832),(595,1800),(583,1755),
        (571,1705),(558,1657),(546,1630),(528,1691),(508,1744),
        (493,1795),(509,1815),(502,1835),(485,1845),(463,1844),
        (435,1838),(414,1823),(387,1805),(362,1786),(338,1779),
        (307,1770),(274,1760),(279,1733),(297,1680),(316,1619),
        (338,1553),(359,1486),(384,1415),(407,1344),(428,1283)], (560,1250), None),
}

# Fine crown/hat contours were reviewed at 2x source resolution. Disconnected
# crown pearls are separate masks, retaining their original white/gold pixels.
BAI["head"] = ([(615,493),(625,500),(636,492),(646,501),(659,493),(668,504),
    (680,496),(692,508),(700,520),(717,521),(723,537),(733,537),(747,539),
    (745,550),(759,548),(774,554),(779,567),(771,580),(758,588),(742,583),
    (736,570),(731,590),(723,612),(711,629),(716,648),(716,675),(713,697),
    (721,718),(730,732),(724,738),(717,738),(720,748),(715,754),(716,763),
    (706,768),(690,765),(673,756),(653,745),(646,765),(649,805),(624,802),(597,785),(600,751),
    (588,742),(570,751),(550,768),(538,767),(543,744),(547,727),(531,728),
    (515,717),(504,704),(504,688),(512,674),(519,667),(516,654),(523,642),
    (524,628),(523,615),(529,604),(542,591),(550,584),(541,577),(523,573),
    (511,561),(502,550),(496,545),(500,540),(517,546),(528,554),(538,557),
    (528,543),(516,532),(509,517),(517,507),(530,503),(548,506),(564,513),
    (575,520),(587,513),(577,503),(578,490),(587,483),(600,483),(610,489)], (642,660),None)
BAI_WING=[(550,655),(535,649),(527,652),(519,668),(503,685),(485,694),
    (469,695),(453,689),(439,680),(428,667),(419,650),(412,631),(409,614),
    (413,609),(426,614),(433,624),(426,622),(430,636),(440,650),(455,664),
    (473,674),(490,677),(504,673),(517,657),(524,640),(530,635),(540,641),(552,645)]
XU["head"] = ([(525,444),(599,444),(613,461),(626,482),(632,498),
    (618,500),(637,504),(660,514),(674,530),(683,544),(677,554),(679,572),
    (677,582),(683,600),(685,626),(680,651),(680,664),(691,681),(691,687),
    (682,690),(683,702),(675,706),(677,716),(673,725),(664,727),(646,724),
    (631,719),(614,719),(604,730),(598,745),(574,742),(562,721),(550,716),
    (546,694),(531,687),(516,677),(511,660),(511,646),(517,630),(513,620),
    (498,631),(477,643),(456,655),(434,673),(411,686),(396,692),(383,692),
    (369,687),(357,675),(351,670),(359,667),(376,672),(389,675),(405,673),
    (426,664),(448,651),(470,633),(492,620),(509,610),(490,604),(473,595),
    (470,581),(477,555),(485,525),(494,500),(507,470)],(598,630),None)
# The rear upper arm is hidden in the photograph. Reuse observed sleeve cloth
# instead of retaining the photographed carrying pole in a background triangle.
XU["right_upper_arm"] = XU["left_upper_arm"]
XU["right_forearm"] = ([(620,990),(650,975),(699,951),(733,938),(768,924),(788,919),
    (798,944),(809,975),(819,1008),(830,1042),(838,1076),(847,1112),(850,1132),
    (833,1137),(801,1133),(766,1126),(733,1111),(703,1090),(660,1070),(625,1035)],(644,1020),(796,929))

# Neck insertion landmarks in the same source coordinate system as the collar.
# The atlas pivots stay unchanged; display offsets align the independently
# scaled head and torso at these anatomical joints, including during head tilt.
NECK = {"baisuzhen": (620,782), "xuxian": (582,732)}
BAI["torso"] = ([(581,772),(598,776),(624,787),(646,804),(658,832)]
    + BAI["torso"][0][4:], BAI["torso"][1], BAI["torso"][2])


def source_mask(size,name,part,outline):
    mask=mask_for(size,outline)
    if name=="baisuzhen" and part=="head":
        extra=Image.new("L",size);draw=ImageDraw.Draw(extra)
        draw.polygon(BAI_WING,fill=255)
        for box in [(610,447,643,481),(646,451,676,484),(676,468,704,506),(700,505,728,535)]:
            draw.ellipse(box,fill=255)
        for start,end in [((623,480),(629,518)),((658,482),(661,515)),((688,504),(686,535))]:
            draw.line([start,end],fill=255,width=4)
        mask=Image.fromarray(np.maximum(np.asarray(mask),np.asarray(extra)))
    return mask


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def dump(path, value):
    temporary=path.with_name(path.name+".tmp")
    with temporary.open("w",encoding="utf-8",newline="\n") as stream:
        stream.write(json.dumps(value, ensure_ascii=False, indent=2)+"\n")
    temporary.replace(path)


def refine_silhouette(image, outline, name):
    """Resolve photographed background at traced edges; preserve white cloth."""
    import cv2
    rgb=np.asarray(image)
    inside=np.asarray(outline)>127
    labels=np.full(inside.shape,cv2.GC_BGD,np.uint8)
    labels[inside]=cv2.GC_PR_FGD
    kernel=np.ones((19,19),np.uint8)
    core=cv2.erode(inside.astype(np.uint8),kernel)>0
    # Crown perforations and the fine headdress ribbon need background models.
    core[:780 if name=="baisuzhen" else 750]=False
    labels[core]=cv2.GC_FGD
    head=inside.copy();head[780:]=False
    labels[head & (rgb.max(axis=2)<100)]=cv2.GC_BGD
    # Seed observed hair/face: these black details belong to the puppet.
    if name=="baisuzhen":
        labels[660:715,632:667]=cv2.GC_FGD
        labels[675:730,675:700]=cv2.GC_FGD
    else:
        labels[650:685,552:575]=cv2.GC_FGD
        labels[641:690,635:671]=cv2.GC_FGD
        labels[500:550,530:575]=cv2.GC_FGD
    cv2.setRNGSeed(20261022)
    cv2.grabCut(rgb,labels,None,np.zeros((1,65)),np.zeros((1,65)),4,cv2.GC_INIT_WITH_MASK)
    keep=((labels==cv2.GC_FGD)|(labels==cv2.GC_PR_FGD)) & inside
    if keep.sum()<inside.sum()*.7:
        raise ValueError("Foreground extraction discarded too much observed garment")
    # GrabCut is only an edge suggestion: retaining photographed black hair,
    # fingers and crown pearls takes precedence over its colour classification.
    from scipy.ndimage import distance_transform_edt
    edge=distance_transform_edt(inside)<4
    keep=inside & (~edge | keep)
    if name=="baisuzhen":
        yy=np.arange(image.height)[:,None]
        keep[(yy<620) & (rgb.max(axis=2)<100)]=False
        # The face has an unambiguous ivory edge against the dark photograph.
        # Trim only its outer edge, retaining interior eyes/brows and black hair.
        for y in range(646,770):
            samples=rgb[y,675:740].astype(np.int16)
            white=(samples.min(axis=1)>180)&(samples.max(axis=1)-samples.min(axis=1)<55)
            xs=np.flatnonzero(white)
            if len(xs)>4:
                keep[y,675+int(xs[-1])+2:]=False
    return Image.fromarray(np.minimum(np.asarray(outline),keep.astype(np.uint8)*255))


def tile(piece, outline, start, end, pivot, forced_scale=None):
    angle = math.pi/2-math.atan2(end[1]-start[1], end[0]-start[0]) if end else 0
    c, s = math.cos(angle), math.sin(angle)
    limits=[]
    bounds=piece.getbbox()
    if bounds is None:
        raise ValueError("Empty source piece")
    # Include disconnected pearls and ornament tips in the atlas fitting bounds.
    for x,y in [(bounds[0],bounds[1]),(bounds[2],bounds[1]),(bounds[2],bounds[3]),(bounds[0],bounds[3])]:
        dx,dy=c*(x-start[0])-s*(y-start[1]),s*(x-start[0])+c*(y-start[1])
        for v,p in [(dx,pivot[0]),(dy,pivot[1])]:
            if abs(v)>1e-6:
                limits.append(((500-p) if v>0 else (p-12))/abs(v))
    length=math.hypot(end[0]-start[0],end[1]-start[1]) if end else 1
    scale=min(limits+([320/length] if end else []))*.97
    if forced_scale is not None:
        scale=min(scale,forced_scale)
    inverse=(c/scale,s/scale,start[0]-(c*pivot[0]+s*pivot[1])/scale,
             -s/scale,c/scale,start[1]-(-s*pivot[0]+c*pivot[1])/scale)
    result=piece.transform((512,512),Image.Transform.AFFINE,inverse,Image.Resampling.BICUBIC)
    return result,scale,scale*length if end else 1


def add_legs(definition, split_x, knee_y, foot_y):
    # Standing uses the intact robe; seated/jump views use these source halves.
    lower=definition["lower_body"][0]
    waist=definition["lower_body"][1]
    for side,sign in [("left",-1),("right",1)]:
        xs=[p[0] for p in lower]
        edge=min(xs)-5 if sign<0 else max(xs)+5
        hip=(waist[0]+sign*24,waist[1])
        knee=(split_x+sign*85,knee_y)
        foot=(split_x+sign*145,foot_y)
        definition[side+"_thigh"] = ([(split_x+sign*-10,waist[1]-26),(edge,waist[1]-26),
            (edge,knee_y+28),(split_x+sign*-10,knee_y+28)],hip,knee)
        definition[side+"_calf"] = ([(split_x+sign*-10,knee_y-28),(edge,knee_y-28),
            (edge,foot_y+12),(split_x+sign*-10,foot_y+12)],knee,foot)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bai",type=Path,required=True)
    parser.add_argument("--xu",type=Path,required=True)
    parser.add_argument("--batch",type=Path,required=True)
    parser.add_argument("--rebuild",action="store_true")
    args=parser.parse_args()
    root=Path(__file__).resolve().parents[1]
    assets=root/"assets/puppets"
    batch=args.batch.resolve()
    before=batch/"before/puppets"
    if before.exists():
        if not args.rebuild:
            raise ValueError("Art backup exists; inspect it before another installation")
        previous=json.loads((assets/"reference-revision.json").read_text(encoding="utf-8"))
        for name,expected in previous["outputs"].items():
            if sha(assets/name)!=expected:raise ValueError("Concurrent art edit: "+name)
    else:
        before.mkdir(parents=True)
        for name in ["puppet_assets.json","baisuzhen.png","xuxian.png","fahai.png"]:
            shutil.copyfile(assets/name,before/name)
    manifest=json.loads((before/"puppet_assets.json").read_text(encoding="utf-8"))
    report=dict(version=1,method="Manually traced original photo pixels, with seeded GrabCut edge cleanup; no generated replacement artwork",
        tool_sha256=sha(Path(__file__)),characters={},limitations=[
        "Reverse sides mirror the supplied face; no independently observed reverse.",
        "Photographs hide rear-arm/leg garment; pieces reuse visible cloth inside the traced silhouette.",
        "Ivory fabric retains photographed illumination; alpha is a display cutout, not measured leather transmittance."])
    board=Image.new("RGB",(1600,1550),"#d8d0b9")
    for index,(name,source,definition) in enumerate([("baisuzhen",args.bai,BAI),("xuxian",args.xu,XU)]):
        image=Image.open(source).convert("RGB")
        if image.size!=(1280,2278):
            raise ValueError(f"Unexpected dimensions: {source}")
        out=batch/name;out.mkdir(exist_ok=True)
        source_path=assets/"source"/(name+"-reference-20261022.jpg")
        if source.resolve()!=source_path.resolve():
            shutil.copyfile(source,source_path)
        skin=manifest["characters"][name]
        reference_facing=skin["reference_facing"]
        source_mirror=float(reference_facing)  # Both supplied photographs face right.
        old_parts=skin["parts"]
        definition=dict(definition)
        add_legs(definition,590 if name=="baisuzhen" else 560,1540,1848)
        full=Image.new("L",image.size)
        for part,(outline,start,end) in definition.items():
            if not part.endswith(("_thigh","_calf")):
                full=Image.fromarray(np.maximum(np.asarray(full),np.asarray(source_mask(image.size,name,part,outline))))
        full=refine_silhouette(image,full,name)
        pieces={}
        silhouette=Image.new("L",image.size)
        for part,(outline,start,end) in definition.items():
            if part.endswith("_thigh") or part.endswith("_calf"):
                alpha=Image.fromarray(np.minimum(np.asarray(mask_for(image.size,outline)),
                    np.asarray(mask_for(image.size,definition["lower_body"][0]))))
            else:
                alpha=source_mask(image.size,name,part,outline)
            alpha=Image.fromarray(np.minimum(np.asarray(alpha),np.asarray(full)))
            rgba=image.copy().convert("RGBA");rgba.putalpha(alpha)
            values=np.asarray(rgba).copy();values[values[:,:,3]==0,:3]=0
            pieces[part]=Image.fromarray(values)
            if not part.endswith(("_thigh","_calf")):
                silhouette=Image.fromarray(np.maximum(np.asarray(silhouette),np.asarray(alpha)))
        cutout=image.convert("RGBA");cutout.putalpha(silhouette)
        cutout.save(out/"cutout.png")
        natural_height=silhouette.getbbox()[3]-silhouette.getbbox()[1]
        atlas=Image.new("RGBA",(2048,2048));parts={};scales={}
        names=list(old_parts)
        for part in ["lower_body","ribbons"]:
            if part in definition and part not in names:names.append(part)
        hand_scale=min(tile(pieces[p],*definition[p],(256,256))[1] for p in ["left_hand","right_hand"])
        for part_index,part in enumerate(names):
            base=part[:-5] if part.endswith("_grip") else part
            outline,start,end=definition[base]
            previous=old_parts.get(part)
            pivot=previous["pivot"] if previous else [256,64] if part=="lower_body" else [256,256]
            result,scale,axis=tile(pieces[base],outline,start,end,pivot,hand_scale if "hand" in part else None)
            if part.startswith("left_hand"):
                result=result.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
            if source_mirror<0:
                result=result.transform((512,512),Image.Transform.AFFINE,
                    (-1,0,2*pivot[0],0,1,0),Image.Resampling.BICUBIC)
            rect=previous["rect"] if previous else [part_index%4*512,part_index//4*512,512,512]
            atlas.paste(result,(rect[0],rect[1]))
            result.save(out/(part+".png"))
            parts[part]=dict(rect=rect,pivot=pivot,axis_pixels=axis,opacity=1.0,
                reference_outline=outline,reference_axis=[start,end] if end else [start],
                method="Source pixels with joint overlap; no backdrop keying")
            scales[part]=scale
        atlas.save(out/"atlas.png",optimize=True)
        skin.update(parts=parts,
            head_size_per_radius=512/(scales["head"]*natural_height*.105),
            hand_size_ratio=512/(hand_scale*natural_height),
            lower_body_size_ratio=[512/(scales["lower_body"]*natural_height),
                512*.44/(scales["lower_body"]*(silhouette.getbbox()[3]-definition["lower_body"][1][1]))],
            palette_layout="User-created source pixels, including ivory/gold and teal garment details",
            reference=dict(filename="source/"+source_path.name,size=list(image.size),sha256=sha(source_path),
                creator="User states these images were created with Doubao",method=report["method"],
                excluded="Photographic stage, background figures, control rods; Xuxian basket and carrying pole"))
        if name=="xuxian":
            skin["shoulder_half_width_ratio"]=.055
        neck=NECK[name]
        origin=definition["torso"][1];end=definition["torso"][2]
        angle=math.pi/2-math.atan2(end[1]-origin[1],end[0]-origin[0])
        factor=.36/math.hypot(end[0]-origin[0],end[1]-origin[1])
        dx,dy=neck[0]-origin[0],neck[1]-origin[1]
        skin["neck_attachment_ratio"]=[source_mirror*factor*(math.cos(angle)*dx-math.sin(angle)*dy),
            factor*(math.sin(angle)*dx+math.cos(angle)*dy)]
        skin["head_neck_offset_ratio"]=[(neck[i]-definition["head"][1][i])/natural_height*(source_mirror if i==0 else 1) for i in range(2)]
        skin["reference"]["neck_insertion_xy"]=list(neck)
        skin["reference"]["canonical_mirror_x"]=source_mirror
        if "ribbons" in parts:
            skin["ribbons_size_ratio"]=512/(scales["ribbons"]*natural_height)
        display=cutout.crop(cutout.getbbox());display.thumbnail((730,1430),Image.Resampling.LANCZOS)
        board.paste(display,(index*800+(800-display.width)//2,45),display)
        font=ImageFont.truetype("C:/Windows/Fonts/msyh.ttc",32)
        ImageDraw.Draw(board).text((index*800+400,1505),"白素贞" if index==0 else "许仙 · 无篮子挑杆",fill="#403b32",font=font,anchor="mm")
        report["characters"][name]=dict(source_sha256=sha(source_path),atlas_sha256=sha(out/"atlas.png"),parts=len(parts),
            intact_robe=True,original_pivots_retained=True)
    staff=manifest["characters"]["fahai"]
    # Rotate the source shaft (tip at upper-left) to point straight upward.
    staff["staff_rotation_rad"]=math.atan2(1109,201)
    # Extend only below the original grip. Reuse the photographed lower shaft,
    # leaving all original atlas tiles, the ornament and the grip unchanged.
    fahai=Image.open(before/"fahai.png").convert("RGBA")
    upright=fahai.crop((512,1536,1024,2048)).rotate(-math.degrees(staff["staff_rotation_rad"]),
        resample=Image.Resampling.BICUBIC,center=(256,256))
    extension=Image.new("RGBA",(512,512))
    extension.paste(upright.crop((248,270,264,310)).resize((16,426),Image.Resampling.BICUBIC),(248,64))
    fahai.paste(extension,(1024,1536))
    fahai.save(assets/"fahai.png",optimize=True)
    staff["parts"]["staff_extension"]=dict(rect=[1024,1536,512,512],pivot=[256,64],
        axis_pixels=426,opacity=1.0,method="Lower shaft source pixels stretched downward from grip")
    staff["staff_down_length_ratio"]=1.1
    report["staff"]=dict(rotation_rad=staff["staff_rotation_rad"],down_length_ratio=1.1,
        orientation="Vertical, fixed in stage axes, follows right wrist; lower shaft may enter the ground")
    for name in ["baisuzhen","xuxian"]:
        shutil.copyfile(batch/name/"atlas.png",assets/(name+".png"))
    dump(assets/"puppet_assets.json",manifest)
    report["outputs"]={name:sha(assets/name) for name in ["puppet_assets.json","baisuzhen.png","xuxian.png","fahai.png"]}
    dump(assets/"reference-revision.json",report)
    audio_path=root/"assets/audio/original-audio-sources.json"
    audio=json.loads(audio_path.read_text(encoding="utf-8"))
    audio.setdefault("previous_puppet_outputs",audio["puppet_outputs"])
    audio["puppet_outputs"]={n:v for n,v in report["outputs"].items()}
    audio["tools"][Path(__file__).name]=sha(Path(__file__))
    dump(audio_path,audio)
    board.save(batch/"source-cutouts.png")
    print(json.dumps(dict(installed=True,parts={n:r["parts"] for n,r in report["characters"].items()},staff_vertical=True)))


if __name__=="__main__":
    main()
