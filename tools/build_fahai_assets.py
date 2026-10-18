"""Rebuild Fahai's cutout atlas from the user-supplied reference. Dev only.

Run: py -3.13 tools/build_fahai_assets.py
Requires Pillow and NumPy. Coordinates refer to the retained 1280 x 1653 JPEG.
"""

from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets" / "puppets"
SOURCE = ASSETS / "source" / "fahai-reference.jpg"
TILE = 512

# Source contours, not invented replacement clothing. Overlapping leather at
# joints is intentional: every movable piece must still meet its neighbour.
PARTS = {
    "head": ([(435, 180), (464, 162), (510, 153), (506, 126), (555, 104),
              (563, 136), (620, 91), (661, 60), (696, 50), (715, 64),
              (727, 106), (729, 164), (722, 224), (710, 250), (739, 269),
              (751, 294), (751, 333), (766, 367), (769, 393), (746, 407),
              (751, 435), (744, 471), (712, 482), (687, 475), (664, 493),
              (657, 512), (584, 513), (584, 482), (587, 438), (562, 424),
              (553, 402), (546, 354), (514, 332), (504, 313), (478, 301),
              (451, 263), (437, 221)], (611, 282), None),
    "torso": ([(575, 505), (621, 510), (660, 522), (680, 550), (686, 605),
               (710, 644), (736, 709), (746, 753), (722, 811), (713, 861),
               (734, 928), (736, 1000), (748, 1127), (750, 1184),
               (713, 1209), (648, 1206), (584, 1190), (528, 1194),
               (462, 1182), (460, 1155), (492, 1087), (515, 996),
               (540, 909), (547, 828), (550, 747), (541, 660), (548, 579)],
              (610, 552), (615, 1080)),
    "left_upper_arm": ([(551, 571), (583, 585), (583, 680), (547, 727),
                        (485, 771), (414, 815), (344, 862), (288, 841),
                        (287, 800), (340, 744), (346, 660), (409, 622),
                        (480, 608)], (546, 635), (354, 817)),
    "left_forearm": ([(288, 789), (352, 811), (389, 855), (377, 894),
                      (349, 955), (339, 1012), (317, 1044), (266, 1047),
                      (217, 1001), (163, 949), (103, 919), (60, 882),
                      (65, 854), (90, 790), (176, 774), (244, 786)],
                     (350, 818), (291, 1039)),
    "left_hand": ([(271, 1015), (305, 1008), (329, 1026), (340, 1055),
                   (323, 1093), (317, 1158), (307, 1162), (299, 1104),
                   (293, 1105), (290, 1159), (280, 1161), (278, 1105),
                   (260, 1083), (259, 1057)], (292, 1034), (300, 1155)),
    "right_upper_arm": ([(666, 624), (706, 648), (749, 693), (805, 723),
                         (841, 762), (827, 814), (789, 839), (748, 816),
                         (713, 782), (681, 737), (667, 690)],
                        (687, 657), (798, 778)),
    "right_forearm": ([(791, 727), (843, 697), (904, 664), (971, 627),
                       (1020, 614), (1063, 616), (1081, 635), (1086, 670),
                       (1117, 718), (1133, 790), (1138, 917), (1101, 926),
                       (1090, 958), (1041, 939), (1005, 912), (1017, 845),
                       (980, 827), (914, 839), (849, 832), (797, 809),
                       (782, 779)], (799, 774), (1073, 650)),
    "right_hand": ([(1064, 613), (1119, 602), (1158, 608), (1209, 605),
                    (1215, 613), (1161, 619), (1160, 632), (1211, 629),
                    (1217, 637), (1164, 645), (1139, 668), (1119, 669),
                    (1080, 651), (1060, 637)], (1080, 635), (1209, 625)),
    "left_thigh": ([(508, 1163), (586, 1177), (620, 1220), (604, 1300),
                    (584, 1380), (535, 1436), (480, 1435), (413, 1399),
                    (365, 1370), (369, 1332), (424, 1247), (463, 1197)],
                   (553, 1196), (503, 1400)),
    "left_calf": ([(432, 1359), (509, 1383), (549, 1420), (559, 1480),
                   (548, 1542), (540, 1606), (540, 1632), (476, 1633),
                   (422, 1619), (412, 1583), (365, 1567), (337, 1526),
                   (359, 1488), (392, 1442)], (494, 1396), (487, 1615)),
    "right_thigh": ([(610, 1166), (689, 1173), (731, 1193), (749, 1288),
                     (782, 1386), (813, 1479), (795, 1511), (736, 1514),
                     (685, 1493), (669, 1426), (650, 1339), (622, 1251)],
                    (668, 1200), (710, 1405)),
    "right_calf": ([(655, 1372), (720, 1392), (754, 1447), (774, 1496),
                    (789, 1535), (810, 1585), (810, 1621), (797, 1640),
                    (734, 1641), (685, 1632), (660, 1625), (666, 1562),
                    (674, 1501), (660, 1449)], (699, 1413), (739, 1615)),
    "ribbons": ([(551, 296), (588, 313), (567, 376), (546, 445),
                 (521, 529), (488, 618), (460, 708), (424, 801),
                 (401, 894), (371, 953), (319, 946), (326, 859),
                 (360, 759), (399, 661), (435, 572), (471, 485),
                 (501, 405), (525, 344)], (549, 367), None),
    "staff": ([(1140, 86), (1154, 89), (1161, 119), (1172, 136),
               (1164, 160), (1175, 181), (1198, 196), (1218, 218),
               (1239, 245), (1233, 282), (1215, 318), (1194, 352),
               (1225, 389), (1238, 422), (1232, 455), (1212, 483),
               (1177, 482), (1152, 451), (1156, 1349), (1175, 1364),
               (1182, 1391), (1169, 1416), (1184, 1445), (1173, 1464),
               (1158, 1471), (1163, 1498), (1146, 1523), (1132, 1500),
               (1130, 1474), (1106, 1462), (1092, 1444), (1105, 1418),
               (1101, 1389), (1108, 1365), (1125, 1353), (1129, 453),
               (1109, 483), (1081, 482), (1066, 467), (1059, 435),
               (1069, 405), (1094, 376), (1073, 349), (1042, 313),
               (1027, 288), (1043, 291), (1038, 251), (1053, 268),
               (1073, 229), (1098, 205), (1113, 190), (1116, 170),
               (1129, 166), (1129, 148), (1123, 136), (1131, 118)],
              (1141, 638), None),
}


def cut_piece(source: Image.Image, outline: list[tuple[int, int]]) -> Image.Image:
    mask = Image.new("L", source.size)
    ImageDraw.Draw(mask).polygon(outline, fill=255)
    rgb = np.asarray(source.convert("RGB"), dtype=np.float32)
    # The JPEG has a white background and white carved lines. This is an
    # estimated display alpha, not measured leather light transmittance.
    alpha = np.clip((255 - rgb.min(axis=2) - 3) / 17, 0, 1)
    alpha *= np.asarray(mask) / 255
    rgba = np.dstack((rgb, alpha * 255)).astype(np.uint8)
    rgba[rgba[:, :, 3] == 0, :3] = 0
    return Image.fromarray(rgba)


def tile_piece(piece, outline, start, end):
    angle = math.pi / 2 - math.atan2(end[1] - start[1], end[0] - start[0]) if end else 0
    c, s = math.cos(angle), math.sin(angle)
    pivot = (256, 100) if end else (256, 256)
    points = [(c * (x-start[0]) - s * (y-start[1]),
               s * (x-start[0]) + c * (y-start[1])) for x, y in outline]
    scales = []
    for x, y in points:
        if x:
            scales.append(((TILE-10-pivot[0]) if x > 0 else (pivot[0]-10)) / abs(x))
        if y:
            scales.append(((TILE-10-pivot[1]) if y > 0 else (pivot[1]-10)) / abs(y))
    length = math.dist(start, end) if end else 1
    scale = min(scales + ([320 / length] if end else []))
    inverse = (c/scale, s/scale, start[0]-(c*pivot[0]+s*pivot[1])/scale,
               -s/scale, c/scale, start[1]-(-s*pivot[0]+c*pivot[1])/scale)
    tile = piece.transform((TILE, TILE), Image.Transform.AFFINE, inverse,
                           resample=Image.Resampling.BICUBIC)
    return tile, {"pivot": list(pivot), "axis_pixels": scale*length if end else 1,
                  "opacity": 1.0, "inferred": False,
                  "reference_outline": outline,
                  "reference_axis": [start, end] if end else [start]}


def main():
    source = Image.open(SOURCE).convert("RGB")
    if source.size != (1280, 1653):
        raise ValueError(f"Unexpected reference dimensions: {source.size}")
    atlas = Image.new("RGBA", (2048, 2048))
    cutout = Image.new("RGBA", source.size)
    parts = {}
    for index, (name, (outline, start, end)) in enumerate(PARTS.items()):
        piece = cut_piece(source, outline)
        cutout.alpha_composite(piece)
        tile, metadata = tile_piece(piece, outline, start, end)
        x, y = index % 4 * TILE, index // 4 * TILE
        atlas.paste(tile, (x, y))
        parts[name] = {"rect": [x, y, TILE, TILE], **metadata}
    atlas.save(ASSETS / "fahai.png", optimize=True)
    art = ROOT / "docs" / "art"
    art.mkdir(parents=True, exist_ok=True)
    cutout.save(art / "fahai-cutout.png", optimize=True)
    manifest_path = ASSETS / "puppet_assets.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    manifest["characters"]["fahai"] = {
        "skin_id": 3, "reference_facing": 1, "head_size_per_radius": 3.75,
        "hand_size_ratio": 0.17, "shoulder_half_width_ratio": 0.075,
        "joint_hex": "#C9A16B", "ink_hex": "#5E3F3B",
        "staff_size_ratio": 1.18, "ribbons_size_ratio": 0.8,
        "reference": {"filename": "source/fahai-reference.jpg", "size": list(source.size),
                      "sha256": hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
                      "method": "Source pixels inside manually traced articulated silhouettes.",
                      "alpha": "White-key estimate; no measured transmittance.",
                      "back": "Mirrored source; independently observed reverse side unavailable."},
        "parts": parts,
    }
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"FAHAI: {len(parts)} parts; atlas={atlas.size}; cutout={cutout.size}")


if __name__ == "__main__":
    main()
