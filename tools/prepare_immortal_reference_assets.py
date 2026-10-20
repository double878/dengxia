"""Prepare articulated immortal puppets from the three user supplied images.

Development only: reuse Pillow/NumPy and the existing atlas convention.
Source photographs and the polygon masks are retained for reproducible edits.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import io
import json
import math
from pathlib import Path
import shutil
from types import SimpleNamespace

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

from build_immortal_assets import ART, OUT, atlas_transform, svg_document

HEAD_SCALE_BY_CHARACTER = {"bailu": .65, "baihe": .65}


# Coordinates refer to each original attachment, including its white margin.
# Each segment has a small overlap at its hinge; visible artwork is never redrawn.
DEFINITIONS = {
    "xianweng": {
        "title": "仙翁", "id": 4, "crop": (184, 32, 579, 765),
        "head": (385, 132), "shoulders": ((308, 255), (441, 254)),
        "elbows": ((269, 369), (493, 359)), "wrists": ((274, 525), (467, 519)),
        "torso_axis": ((375, 232), (369, 450)),
        "hips": ((338, 450), (409, 450)), "knees": ((322, 601), (428, 601)),
        "feet": ((308, 738), (430, 739)),
        "polygons": {
            "head": [(381,37),(421,47),(446,76),(450,110),(444,126),(457,141),(453,156),(443,157),(450,184),(456,224),(462,267),(449,312),(431,328),(419,288),(409,249),(394,219),(370,201),(350,181),(347,153),(331,161),(314,132),(314,106),(327,76),(349,51)],
            "torso": [(328,177),(393,176),(430,229),(449,326),(455,401),(444,470),(299,475),(303,440),(297,367),(310,282),(288,251)],
            "left_upper_arm": [(286,238),(329,253),(314,347),(305,397),(240,408),(215,376),(254,294)],
            "left_forearm": [(225,351),(305,352),(305,437),(298,500),(244,527),(187,531),(188,475),(204,411)],
            "left_hand": [(249,513),(288,504),(298,558),(268,569),(247,550)],
            "right_upper_arm": [(411,239),(461,265),(498,310),(527,365),(502,399),(452,387),(439,328)],
            "right_forearm": [(457,343),(519,337),(552,430),(575,509),(561,530),(454,510),(444,468)],
            "right_hand": [(449,501),(482,506),(491,534),(475,558),(448,555)],
            "left_thigh": [(306,430),(370,425),(374,604),(273,628),(278,551)],
            "left_calf": [(280,587),(374,585),(384,729),(345,752),(275,765),(246,734),(263,667)],
            "right_thigh": [(361,429),(443,430),(467,603),(378,628),(357,604)],
            "right_calf": [(361,587),(469,590),(515,730),(468,756),(405,765),(371,748)],
        },
    },
    "baihe": {
        "title": "鹤童", "id": 6, "crop": (159, 36, 650, 766),
        "head": (364, 151), "shoulders": ((325, 275), (419, 273)),
        "elbows": ((262, 329), (481, 275)), "wrists": ((263, 444), (584, 272)),
        "torso_axis": ((369, 258), (371, 545)),
        "hips": ((343, 542), (412, 543)), "knees": ((323, 630), (434, 632)),
        "feet": ((322, 740), (445, 743)),
        "polygons": {
            "head": [(259,38),(426,36),(442,192),(414,233),(341,230),(328,211),(300,225),(295,202)],
            "torso": [(342,213),(392,219),(435,247),(464,247),(455,284),(430,296),(437,353),(460,415),(478,550),(375,565),(290,542),(308,480),(327,403),(321,312),(263,279),(259,263),(304,239)],
            "left_upper_arm": [(296,276),(334,283),(299,331),(290,354),(238,354),(221,335),(258,299)],
            "left_forearm": [(244,306),(288,324),(294,429),(282,451),(237,452),(163,426),(169,405),(205,356)],
            "left_hand": [(245,435),(278,437),(279,466),(261,506),(244,497)],
            "right_upper_arm": [(433,254),(483,248),(503,253),(509,293),(476,309),(442,290)],
            "right_forearm": [(465,251),(577,250),(595,259),(591,301),(578,359),(565,360),(500,322),(462,286)],
            "right_hand": [(574,255),(649,254),(650,280),(599,289),(576,280)],
            "left_thigh": [(320,529),(389,532),(388,639),(343,665),(275,655),(288,593)],
            "left_calf": [(302,591),(371,604),(393,716),(368,755),(319,766),(280,741),(221,727),(222,692),(255,653)],
            "right_thigh": [(382,531),(476,536),(474,616),(465,663),(396,650)],
            "right_calf": [(411,590),(461,585),(490,646),(521,722),(494,744),(441,766),(402,763),(396,713)],
        },
    },
    "bailu": {
        "title": "鹿童", "id": 5, "crop": (151, 20, 637, 754),
        "head": (343, 125), "shoulders": ((310, 254), (388, 246)),
        "elbows": ((243, 299), (462, 253)), "wrists": ((213, 397), (563, 255)),
        "torso_axis": ((348, 239), (365, 511)),
        "hips": ((330, 516), (399, 522)), "knees": ((294, 607), (401, 607)),
        "feet": ((285, 720), (428, 727)),
        "polygons": {
            "head": [(229,21),(366,21),(424,125),(418,180),(374,203),(367,220),(341,210),(317,197),(309,172),(286,183),(224,231),(226,197),(269,155),(231,119)],
            "torso": [(315,202),(368,204),(399,223),(420,273),(410,375),(429,435),(459,536),(378,538),(263,519),(285,458),(303,393),(292,309),(281,264)],
            "left_upper_arm": [(284,255),(324,265),(291,306),(273,327),(221,328),(217,295),(253,274)],
            "left_forearm": [(231,277),(270,294),(270,381),(250,407),(216,409),(156,382),(160,355),(195,312)],
            "left_hand": [(187,387),(233,395),(239,427),(206,467),(187,456)],
            "right_upper_arm": [(385,229),(456,228),(482,231),(490,273),(464,290),(403,267)],
            "right_forearm": [(446,226),(563,225),(574,245),(573,309),(559,319),(475,291),(446,272)],
            "right_hand": [(558,239),(635,235),(636,268),(589,279),(558,270)],
            "left_thigh": [(292,509),(369,511),(355,582),(326,634),(290,645),(251,621),(260,571)],
            "left_calf": [(263,587),(326,589),(310,690),(337,728),(285,754),(228,725),(226,699)],
            "right_thigh": [(358,513),(443,525),(449,578),(429,635),(389,651),(343,610),(350,561)],
            "right_calf": [(370,587),(435,589),(438,699),(479,710),(480,740),(420,754),(384,742)],
        },
    },
}


def remove_background(source: Image.Image, crop: tuple, seed: tuple) -> Image.Image:
    rgb = np.asarray(source.convert("RGB"))
    low = rgb.min(axis=2).astype(np.float32)
    chroma = rgb.max(axis=2).astype(np.int16) - rgb.min(axis=2)
    paper = Image.fromarray(((low >= 234) & (chroma <= 26)).astype(np.uint8) * 255)
    for corner in ((0, 0), (source.width - 1, 0), (0, source.height - 1), (source.width - 1, source.height - 1)):
        if paper.getpixel(corner) == 255:
            ImageDraw.floodfill(paper, corner, 128)
    outside = np.asarray(paper) == 128
    # Only essentially pure white interior pixels count as photographed cutouts.
    holes = (low >= 244) & (chroma <= 14)
    alpha = np.full(low.shape, 255, dtype=np.uint8)
    alpha[outside | holes] = 0
    # Feather only next to removed paper, retaining the warm white sleeves/beard.
    edge = np.asarray(Image.fromarray((alpha == 0).astype(np.uint8) * 255).filter(ImageFilter.MaxFilter(3))) > 0
    alpha[edge] = np.minimum(alpha[edge], np.clip((253 - low[edge]) * 24, 0, 255).astype(np.uint8))
    frame = np.zeros_like(alpha)
    x0, y0, x1, y1 = crop
    frame[y0:y1, x0:x1] = 255
    alpha = np.minimum(alpha, frame)
    # Remove isolated paper flecks left by the photographed background texture.
    connected = Image.fromarray((alpha > 24).astype(np.uint8) * 255).filter(ImageFilter.MaxFilter(3))
    if connected.getpixel(seed) != 255:
        raise ValueError("The foreground seed must lie on the puppet")
    ImageDraw.floodfill(connected, seed, 128)
    alpha[np.asarray(connected) != 128] = 0
    return Image.fromarray(np.dstack((rgb, alpha)), "RGBA")


def masked(image: Image.Image, polygon: list) -> Image.Image:
    mask = Image.new("L", image.size)
    ImageDraw.Draw(mask).polygon(polygon, fill=255)
    result = image.copy()
    result.putalpha(Image.fromarray(np.minimum(np.asarray(image.getchannel("A")), np.asarray(mask))))
    return result


def axes(definition: dict) -> dict:
    result = {"head": (definition["head"], None, "torso"),
              "torso": (*definition["torso_axis"], "root"),
              "lower_body": (definition["torso_axis"][1], None, "root")}
    for i, side in enumerate(("left", "right")):
        shoulder, elbow, wrist = (definition[key][i] for key in ("shoulders", "elbows", "wrists"))
        # Hands point down in their tiles. The renderer mirrors the left tile.
        direction = np.asarray(wrist) - elbow
        direction = direction / np.linalg.norm(direction)
        result[side + "_upper_arm"] = (shoulder, elbow, "torso")
        result[side + "_forearm"] = (elbow, wrist, side + "_upper_arm")
        result[side + "_hand"] = (wrist, tuple(np.asarray(wrist) + direction * 35), side + "_forearm")
        result[side + "_thigh"] = (definition["hips"][i], definition["knees"][i], "root")
        result[side + "_calf"] = (definition["knees"][i], definition["feet"][i], side + "_thigh")
    return result


def warp_piece(piece: Image.Image, matrix: np.ndarray) -> Image.Image:
    rgba = np.asarray(piece).astype(np.float32) / 255
    rgba[:, :, :3] *= rgba[:, :, 3:4]
    inverse = np.linalg.inv(np.vstack((matrix, [0, 0, 1])))[:2].ravel()
    warped = np.stack([np.asarray(Image.fromarray(rgba[:, :, channel]).transform(
        (512, 512), Image.Transform.AFFINE, inverse, Image.Resampling.BICUBIC)) for channel in range(4)], axis=2)
    warped = np.clip(warped, 0, 1)
    warped[:, :, :3] /= np.maximum(warped[:, :, 3:4], 1 / 255)
    return Image.fromarray(np.clip(warped * 255, 0, 255).astype(np.uint8), "RGBA")


def embedded(image: Image.Image) -> str:
    buffer = io.BytesIO()
    image.save(buffer, format="PNG")
    data = base64.b64encode(buffer.getvalue()).decode("ascii")
    return f'<image width="{image.width}" height="{image.height}" href="data:image/png;base64,{data}"/>'


def assembled(key: str, definition: dict, pieces: dict) -> str:
    def piece(name):
        # Embedding cropped pieces keeps the editable inspection page compact.
        box = pieces[name].getbbox()
        return f'<g data-piece="{name}"><g transform="translate({box[0]} {box[1]})">{embedded(pieces[name].crop(box))}</g></g>'

    def joint(name, at, content):
        return f'<g id="{key}-{name}" data-pivot="{at[0]},{at[1]}">{content}</g>'

    legs, arms = [], []
    for i, side in enumerate(("left", "right")):
        legs.append(joint(side + "_hip", definition["hips"][i], piece(side + "_thigh") +
                          joint(side + "_knee", definition["knees"][i], piece(side + "_calf"))))
        arms.append(joint(side + "_arm", definition["shoulders"][i], piece(side + "_upper_arm") +
                          joint(side + "_elbow", definition["elbows"][i], piece(side + "_forearm") + piece(side + "_hand"))))
    scale = HEAD_SCALE_BY_CHARACTER.get(key, 1.0)
    neck = (definition["head"][0], pieces["head"].getbbox()[3] - 6)
    head = f'<g transform="translate({neck[0]} {neck[1]}) scale({scale}) translate({-neck[0]} {-neck[1]})">{piece("head")}</g>'
    upper = arms[0] + piece("torso") + arms[1] + joint("head", definition["head"], head)
    return f'<g id="{key}-figure">{"".join(legs)}{joint("waist", definition["torso_axis"][1], upper)}</g>'


def build(references: dict[str, Path]) -> None:
    source_dir = OUT / "source"
    source_dir.mkdir(parents=True, exist_ok=True)
    (source_dir / ".gdignore").touch()
    ART.mkdir(parents=True, exist_ok=True)
    manifest = {"version": 1, "atlas_size": [2048, 2048], "tile_size": [512, 512],
                "part_coordinate_space": "各角色用户原图的像素坐标；原图白边计入坐标。",
                "reference": {"method": "用户提供的三张原图直接抠图、分件；没有重新绘制脸部与纹样。",
                              "back": "未提供反面；同一组分件整体镜像。",
                              "alpha": "白色背景和近纯白镂空去除；染皮透光沿用舞台材质。"},
                "characters": {}}
    figures, report = [], []
    board = Image.new("RGB", (1800, 1050), "#eee8da")
    font = ImageFont.truetype("C:/Windows/Fonts/simsun.ttc", 31)
    for column, key in enumerate(("bailu", "baihe", "xianweng")):
        definition = DEFINITIONS[key]
        source = source_dir / (key + "-reference.png")
        if references.get(key):
            shutil.copyfile(references[key], source)
        original = Image.open(source).convert("RGB")
        start, end = definition["torso_axis"]
        seed = (round((start[0] + end[0]) / 2), round((start[1] + end[1]) / 2))
        image = remove_background(original, definition["crop"], seed)
        image.save(ART / (key + "-pose.png"))
        pieces = {name: masked(image, polygon) for name, polygon in definition["polygons"].items()}
        # Keep the continuous trousers/robe silhouette instead of forcing an
        # intact photographed skirt onto two artificially separated leg chains.
        waist_y = definition["torso_axis"][1][1]
        overlap = 24
        lower_polygon = ([(310,425),(440,425),(453,552),(478,648),(515,730),(470,757),
                          (404,765),(335,765),(274,765),(246,734),(272,651),(293,548)]
                         if key == "xianweng" else
                         [(definition["crop"][0], waist_y - overlap),
                          (definition["crop"][2], waist_y - overlap),
                          (definition["crop"][2], image.height),
                          (definition["crop"][0], image.height)])
        pieces["lower_body"] = masked(image, lower_polygon)
        atlas = Image.new("RGBA", (2048, 2048))
        parts, scales = {}, {}
        hand_scales = [atlas_transform(SimpleNamespace(pivot=start, end=end, bounds=pieces[name].getbbox()))[1]
                       for name, (start, end, _) in axes(definition).items() if name.endswith("_hand")]
        for index, (name, (start, end, parent)) in enumerate(axes(definition).items()):
            piece = pieces[name]
            bounds = piece.getbbox()
            if not bounds:
                raise ValueError(f"Empty source piece: {key}/{name}")
            angle, scale, pivot, axis = atlas_transform(SimpleNamespace(pivot=start, end=end, bounds=bounds))
            if name.endswith("_hand"):
                scale = min(hand_scales)
            # Bicubic interpolation extends a source edge by up to two pixels.
            scale *= .94
            if end:
                axis = scale * math.dist(start, end)
            c, s = math.cos(angle) * scale, math.sin(angle) * scale
            matrix = np.array([[c, -s, pivot[0] - c * start[0] + s * start[1]],
                               [s, c, pivot[1] - s * start[0] - c * start[1]]])
            tile = warp_piece(piece, matrix)
            if name == "left_hand":
                tile = tile.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
                pivot = (512 - pivot[0], pivot[1])
            x, y = index % 4 * 512, index // 4 * 512
            atlas.paste(tile, (x, y))
            parts[name] = {"rect": [x, y, 512, 512], "pivot": list(pivot), "axis_pixels": axis,
                           "parent": parent, "reference_axis": [list(start)] + ([list(end)] if end else []),
                           "reference_bounds": list(bounds), "opacity": 1.0,
                           "reconstruction": "原图直接提取；接缝保留少量重叠。"}
            scales[name] = scale
            alpha = np.asarray(tile.getchannel("A"))
            if np.any(alpha[:8]) or np.any(alpha[-8:]) or np.any(alpha[:, :8]) or np.any(alpha[:, -8:]):
                raise ValueError(f"Clipped tile: {key}/{name}")
        atlas.save(OUT / (key + ".png"))
        # Existing SVG paths stay meaningful and mirror the current PNG artwork.
        (OUT / (key + ".svg")).write_text(svg_document(embedded(atlas), 2048, 2048), encoding="utf-8")
        natural_height = image.getbbox()[3] - image.getbbox()[1]
        manifest["characters"][key] = {
            "name_zh": definition["title"], "skin_id": definition["id"], "reference_facing": 1,
            "atlas": key + ".png", "editable": key + ".svg",
            "head_size_per_radius": 512 * HEAD_SCALE_BY_CHARACTER.get(key, 1.0) / (scales["head"] * natural_height * .105),
            "head_scale": HEAD_SCALE_BY_CHARACTER.get(key, 1.0),
            "lower_body_size_ratio": [512 / (scales["lower_body"] * natural_height),
                                       512 * .44 / (scales["lower_body"] * (image.getbbox()[3] - waist_y))],
            "hand_size_ratio": 512 / (scales["right_hand"] * natural_height),
            "shoulder_half_width_ratio": abs(definition["shoulders"][1][0] - definition["shoulders"][0][0]) * .18 / math.dist(*definition["torso_axis"]),
            "joint_hex": "#b99a5e", "ink_hex": "#302e22",
            "parts": parts, "layout": {"canvas_size": list(image.size), "head_pivot": list(definition["head"]),
                                        "waist": list(definition["torso_axis"][1])},
            "reference": {"filename": "source/" + source.name, "size": list(original.size),
                          "sha256": hashlib.sha256(source.read_bytes()).hexdigest()},
            "registration": "额外外观 4/5/6；当前第三幕鹿童沿用编号 5。"}
        art = assembled(key, definition, pieces)
        svg = svg_document(art, image.width, image.height)
        (ART / (key + "-pose.svg")).write_text(svg, encoding="utf-8")
        figures.append(f'<div class="actor" data-character="{key}"><div class="actor-label"><strong>{definition["title"]}</strong></div><div class="flip">{svg}</div></div>')
        display = image.crop(image.getbbox())
        display.thumbnail((535, 900), Image.Resampling.LANCZOS)
        board.paste(display, (column * 600 + (600 - display.width) // 2, 65 + (900 - display.height)), display)
        ImageDraw.Draw(board).text((column * 600 + 300, 1010), definition["title"], font=font, fill="#423b2e", anchor="mm")
        report.append({"character": key, "size": list(atlas.size), "parts": len(parts), "tile_edges": "clear",
                       "source_sha256": manifest["characters"][key]["reference"]["sha256"]})
    (OUT / "immortals-assets.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    board.save(ART / "lineup.png")
    (ART / "asset-checks.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    template = (Path(__file__).parent / "immortal_preview.html").read_text(encoding="utf-8")
    template = template.replace("{{FIGURES}}", "".join(figures)).replace("560,box.x", "757,box.x").replace("1010,box.y", "800,box.y")
    template = template.replace("鹿角冠、鹤形冠与高额长须，保留参考影人的侧面轮廓与袍服配色。", "按三张新参考图提取原图形象，保留莲花冠、羽冠、鹿纹衣与红金寿纹袍。")
    template = template.replace("白鹿：鹿角冠 · 赭红脸 · 深绿袍", "鹿童：莲花冠 · 鹿纹衣 · 青蓝裤靴").replace("白鹤：鹤形冠 · 白脸黑线 · 深青袍", "鹤童：羽冠红缨 · 青色云肩 · 白衣羽纹").replace("仙翁：高额 · 白须 · 黄袍 · 拄杖", "仙翁：高额白须 · 红披肩 · 金色寿纹袍")
    template = template.replace("低清参考无法辨认的纹样与关节连接处已补绘", "形象直接取自用户提供的三张新图；白色底已去除，关节保留重叠")
    (ART / "preview.html").write_text(template, encoding="utf-8")
    print("REFERENCE_ASSET_CHECKS", json.dumps(report, ensure_ascii=False))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for key in DEFINITIONS:
        parser.add_argument("--" + key, type=Path)
    args = parser.parse_args()
    build({key: getattr(args, key) for key in DEFINITIONS})
