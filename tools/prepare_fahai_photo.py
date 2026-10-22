"""Trace this task's Fahai photo into a staged atlas, retaining source pixels.

This is a cutout workflow, not image generation. Occluded strips are marked as
inferred and filled only from adjacent pixels of the same reference piece.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil

import numpy as np
from PIL import Image, ImageDraw
from scipy.ndimage import distance_transform_edt

from build_fahai_assets import tile_piece

PARTS = {
    "head": ([(458,326),(470,320),(506,326),(538,313),(550,302),
              (551,270),(553,226),(558,244),(562,267),(570,286),
              (579,301),(604,284),(643,252),(678,227),(699,221),
              (714,225),(722,239),(728,264),(727,312),(724,354),
              (722,391),(736,411),(745,444),(745,472),(735,492),
              (753,509),(757,520),(751,527),(734,525),(726,535),
              (733,547),(731,568),(724,575),(730,590),(723,611),
              (706,620),(687,615),(672,602),(652,590),(647,571),
              (630,575),(628,626),(626,644),(588,637),(590,596),
              (593,557),(584,521),(576,490),(575,460),(550,461),
              (516,451),(493,431),(477,405),(463,371),(458,342)], (611,450), None),
    "ribbons": ([(539,457),(566,459),(582,471),(592,493),(585,527),
                  (568,555),(543,575),(518,590),(491,604),(461,617),
                  (435,626),(421,622),(417,608),(422,596),(445,576),
                  (474,549),(497,527),(520,507),(533,483)], (556,473), None),
    "torso": ([(567,645),(600,640),(634,649),(654,672),(664,710),
               (662,753),(665,790),(662,833),(658,874),(653,922),
               (650,979),(636,1013),(611,1034),(582,1044),(554,1042),
               (523,1036),(496,1021),(475,1007),(461,992),(471,970),
               (482,942),(495,906),(510,858),(528,804),(545,754),
               (548,706),(554,670)], (602,676), (582,1007)),
    "left_upper_arm": ([(557,698),(569,724),(566,751),(545,773),
                        (509,768),(472,754),(425,740),(386,733),
                        (345,722),(315,708),(309,680),(324,651),
                        (344,643),(375,655),(411,676),(446,699),
                        (481,722),(515,729),(542,706)], (553,733), (330,694)),
    "left_forearm": ([(322,711),(301,687),(284,656),(269,626),(254,591),
                      (227,555),(207,521),(186,490),(167,457),
                      (151,424),(139,395),(162,383),(198,370),
                      (238,360),(277,352),(303,349),(328,355),
                      (361,364),(394,374),(416,385),(415,423),
                      (411,469),(404,515),(397,558),(389,603),
                      (383,645),(378,670),(354,693)], (330,687), (380,387)),
    "left_hand": ([(367,342),(371,322),(379,290),(393,263),(404,238),
                   (416,222),(423,224),(414,247),(404,276),
                   (410,281),(421,250),(432,231),(440,230),
                   (439,239),(429,269),(427,288),(435,307),
                   (428,326),(416,338),(405,350),(386,358)], (390,349), (415,285)),
    "right_upper_arm": ([(648,724),(675,697),(702,669),(727,643),
                         (749,622),(777,606),(799,613),(817,636),
                         (834,659),(824,685),(798,706),(765,715),
                         (733,724),(702,736),(673,751),(649,762)], (650,722), (792,671)),
    "right_forearm": ([(788,631),(817,609),(843,579),(870,543),
                       (898,508),(928,474),(956,448),(983,428),
                       (1008,419),(1025,427),(1044,447),(1055,473),
                       (1071,506),(1088,545),(1105,583),(1122,626),
                       (1149,660),(1152,675),(1135,687),(1119,696),
                       (1090,692),(1060,679),(1024,668),(991,666),
                       (956,674),(918,686),(883,693),(858,691),
                       (841,678),(822,656)], (814,660), (1021,449)),
    "right_hand": ([(1004,435),(1006,410),(1019,397),(1047,385),
                    (1077,379),(1095,375),(1091,383),(1071,394),
                    (1084,396),(1106,397),(1107,403),(1096,407),
                    (1077,412),(1066,420),(1081,423),(1090,420),
                    (1093,425),(1084,435),(1068,442),(1052,446),
                    (1034,448),(1017,445)], (1020,440), (1091,400)),
    # Source pose hides the upper standing thigh behind the raised leg.
    # The visible garment is mapped to the existing thigh axis, not invented.
    "left_thigh": ([(580,1196),(611,1190),(643,1213),(672,1256),
                    (688,1288),(687,1329),(680,1373),(675,1416),
                    (639,1428),(601,1423),(565,1413),(533,1403),
                    (506,1389),(524,1351),(540,1310),(551,1267),
                    (565,1227)], (596,1220), (588,1394)),
    "left_calf": ([(539,1358),(582,1369),(629,1372),(676,1373),
                   (681,1416),(685,1462),(686,1517),(681,1545),
                   (680,1587),(687,1622),(684,1656),(675,1666),
                   (641,1669),(607,1670),(577,1669),(568,1663),
                   (545,1655),(518,1643),(493,1631),(479,1621),
                   (490,1611),(478,1604),(490,1592),(478,1586),
                   (491,1575),(487,1565),(511,1552),(532,1536),
                   (548,1511),(532,1498),(514,1488),(489,1477),
                   (477,1467),(474,1453),(480,1436),(494,1413),
                   (510,1390)], (579,1392), (602,1645)),
    "right_thigh": ([(500,983),(537,980),(577,979),(615,977),
                     (652,982),(692,1002),(736,1023),(780,1038),
                     (809,1044),(826,1062),(831,1091),(817,1127),
                     (796,1158),(773,1192),(751,1226),(724,1254),
                     (700,1274),(681,1285),(663,1287),(639,1273),
                     (616,1251),(593,1223),(566,1195),(539,1168),
                     (516,1141),(498,1114),(487,1080),(483,1047),
                     (488,1011)], (551,1039), (792,1105)),
    "right_calf": ([(790,1044),(817,1048),(837,1067),(846,1106),
                    (854,1156),(863,1205),(876,1254),(891,1303),
                    (908,1336),(917,1347),(914,1366),(902,1375),
                    (895,1392),(910,1410),(921,1434),(924,1457),
                    (916,1475),(897,1481),(870,1485),(839,1491),
                    (811,1493),(790,1490),(773,1487),(757,1477),
                    (752,1467),(756,1428),(758,1394),(741,1385),
                    (710,1382),(694,1380),(704,1344),(706,1296),
                    (719,1254),(738,1207),(755,1165),(771,1123)], (805,1091), (838,1465)),
    "staff": ([(171,236),(181,236),(208,242),(218,235),(228,235),
               (236,244),(249,242),(267,246),(287,250),(302,250),
               (310,256),(326,253),(338,254),(348,260),(380,265),
               (400,274),(1279,440),(1279,463),(396,297),
               (377,284),(347,279),(337,283),(326,286),(314,281),
               (307,276),(289,275),(267,269),(254,270),(244,266),
               (231,264),(218,259),(206,257),(174,250)], (1049,402), None),
}
POLE = [(170,232),(1279,433),(1279,465),(170,264)]


def mask_for(size, outline):
    # Supersample the hand-traced outline rather than keying leather colours.
    mask = Image.new("L", (size[0] * 2, size[1] * 2))
    ImageDraw.Draw(mask).polygon([(x*2, y*2) for x, y in outline], fill=255)
    return mask.resize(size, Image.Resampling.LANCZOS)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--batch", type=Path, required=True)
    args = parser.parse_args()
    source = Image.open(args.source).convert("RGB")
    if source.size != (1280, 1821):
        raise ValueError(f"Unexpected reference dimensions: {source.size}")
    out = args.batch.resolve() / "art"
    out.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(args.source, out / "fahai-reference.jpg")
    atlas = Image.new("RGBA", (2048, 2048))
    cutout = Image.new("RGBA", source.size)
    pole = np.asarray(mask_for(source.size, POLE)) > 127
    parts = {}
    repaired = {}
    for index, (name, (outline, start, end)) in enumerate(PARTS.items()):
        alpha = np.asarray(mask_for(source.size, outline)).copy()
        rgb = np.asarray(source).copy()
        repair = np.zeros(alpha.shape, bool)
        if name in ["head", "left_hand"]:
            repair = pole & (alpha > 127)
            known = (alpha > 127) & ~pole
            _, nearest = distance_transform_edt(~known, return_indices=True)
            rgb[repair] = rgb[nearest[0][repair], nearest[1][repair]]
            # Interpolate the concealed strip between observed edges, instead
            # of leaving a discontinuous nearest-neighbour seam through the hat.
            for x in np.flatnonzero(repair.any(axis=0)):
                missing = np.flatnonzero(repair[:, x])
                above = np.flatnonzero(known[:missing[0], x])
                below = np.flatnonzero(known[missing[-1]+1:, x]) + missing[-1]+1
                if len(above) and len(below):
                    top, bottom = above[-1], below[0]
                    weight = ((missing-top) / (bottom-top))[:, None]
                    rgb[missing, x] = np.rint(rgb[top, x]*(1-weight) + rgb[bottom, x]*weight).astype(np.uint8)
        elif name == "staff":
            # The glove conceals a short section of the pole; reuse observed
            # wooden pole pixels with the same perpendicular offset.
            yy, xx = np.indices(alpha.shape)
            repair = (xx >= 1007) & (xx <= 1105) & (alpha > 127)
            donor_y = np.clip(np.rint(yy + (1160 - xx) * 201 / 1109).astype(int), 0, source.height-1)
            rgb[repair] = rgb[donor_y[repair], 1160]
        rgba = np.dstack((rgb, alpha))
        rgba[alpha == 0, :3] = 0
        piece = Image.fromarray(rgba, "RGBA")
        piece.save(out / (name + ".png"), optimize=True)
        cutout.alpha_composite(piece)
        tile, metadata = tile_piece(piece, outline, start, end)
        x, y = index % 4 * 512, index // 4 * 512
        atlas.paste(tile, (x, y))
        metadata["inferred"] = bool(repair.any())
        parts[name] = dict(rect=[x, y, 512, 512], **metadata)
        repaired[name] = int(repair.sum())
    atlas.save(out / "fahai.png", optimize=True)
    cutout.save(out / "fahai-cutout.png", optimize=True)
    # A neutral checkerboard makes retained background and clipped edges visible.
    board = Image.new("RGB", source.size, "#ddd6c7")
    draw = ImageDraw.Draw(board)
    for y in range(0, source.height, 32):
        for x in range(0, source.width, 32):
            if (x // 32 + y // 32) % 2:
                draw.rectangle((x, y, x+31, y+31), fill="#b7b0a3")
    board.paste(cutout, mask=cutout.getchannel("A"))
    board.resize((768, round(source.height*.6)), Image.Resampling.LANCZOS).save(out / "fahai-preview.jpg")
    # The new photo has a shorter hair piece than the former reference. Fit its
    # visible size to the head after the actual game pose review; pivots stay put.
    root = Path(__file__).resolve().parents[1]
    old = json.loads((root / "assets/puppets/puppet_assets.json").read_text(encoding="utf-8"))["characters"]["fahai"]
    skin = {k: v for k, v in old.items() if k not in ["parts", "reference"]}
    skin["ribbons_size_ratio"] = .25
    skin["hand_size_ratio"] = .13
    parts["right_thigh"]["width_scale"] = .72
    parts["left_thigh"]["width_scale"] = .86
    skin.update(parts=parts, reference=dict(filename="source/fahai-reference-20261022.jpg", size=list(source.size),
        sha256=hashlib.sha256(args.source.read_bytes()).hexdigest(),
        method="Manually traced source-pixel articulated cutout; see staged limitations.",
        alpha="Opaque leather with traced anti-aliased boundary; not measured transmittance.",
        back="Mirrored source, not a separately observed reverse.",
        repair_pixels=repaired))
    manifest = dict(status="staged_visual_draft", game_assets_installed=False,
        character=skin, atlas_sha256=hashlib.sha256((out / "fahai.png").read_bytes()).hexdigest(),
        tool_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        limitations=["Source pose obscures upper standing thigh; only observed garment mapped to thigh axis.",
                     "A narrow staff occlusion in hat/hand is filled from nearest observed pixels of the same piece.",
                     "Glove occlusion in staff uses observed wooden pole pixels; far tip ends at source image edge.",
                     "Presentation ratios calibrated to the new source in the actual game pose sheet."])
    (out / "fahai-manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(json.dumps(dict(parts=len(parts), atlas=list(atlas.size), repaired_pixels=repaired)))


if __name__ == "__main__":
    main()
