"""Prepare an articulated white-snake cutout from the user reference, dev only.

Retains the painted head and sampled scale texture. Coils, missing edges and
overlapping leather are reconstructed for articulation; this is not a claim of
pixel-perfect extraction. Pillow/NumPy are not runtime dependencies.
"""
from pathlib import Path
import hashlib
import json
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/puppets/snake"
SOURCE = OUT / "snake-reference.jpg"


def texture(size):
    src = Image.open(SOURCE).convert("RGB").resize((922, 2048))
    patch = src.crop((620, 1100, 740, 1210))
    rgb = np.asarray(patch).astype(np.float32)
    # The sampled scale patch is separated from the original brown support.
    gray = np.clip(rgb.mean(axis=2) / 255, 0.52, 1.0)
    base = np.array([230, 225, 206], dtype=np.float32)
    rgb = np.clip(base[None, None, :] * (0.80 + gray[:, :, None] * 0.20), 0, 255).astype(np.uint8)
    tile = Image.fromarray(rgb).convert("RGBA")
    canvas = Image.new("RGBA", size)
    for y in range(0, size[1], tile.height):
        for x in range(0, size[0], tile.width):
            canvas.paste(tile, (x, y))
    return canvas


def masked(mask, name):
    canvas = texture(mask.size)
    edge = mask.filter(ImageFilter.MaxFilter(5))
    outline = Image.new("RGBA", mask.size, (88, 78, 54, 255))
    outline.putalpha(edge)
    canvas.putalpha(mask)
    outline.alpha_composite(canvas)
    outline.save(OUT / name)


def bezier(points):
    p = np.asarray(points, dtype=float)
    t = np.linspace(0, 1, 64)[:, None]
    q = (1-t)**3*p[0] + 3*(1-t)**2*t*p[1] + 3*(1-t)*t**2*p[2] + t**3*p[3]
    return [tuple(v) for v in q]


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    src = Image.open(SOURCE).convert("RGBA").resize((922, 2048))
    head_points = [(523, 490), (539, 468), (539, 448), (565, 432),
                   (588, 420), (617, 410), (652, 405), (683, 409),
                   (703, 427), (690, 451), (683, 487), (666, 525),
                   (644, 548), (622, 565), (592, 593), (560, 597),
                   (540, 586), (523, 573), (519, 549), (530, 527)]
    head_mask = Image.new("L", src.size)
    ImageDraw.Draw(head_mask).polygon(head_points, fill=255)
    src.putalpha(head_mask)
    head = src.crop((515, 400, 710, 625))
    # Brown gaps outside the snake inside the hand-traced contour are removed.
    pix = np.asarray(head).copy()
    rgb = pix[:, :, :3].astype(np.int16)
    brown = ((rgb[:, :, 0] - rgb[:, :, 1]) > 18) & ((rgb[:, :, 1] - rgb[:, :, 2]) > 20) & (rgb.mean(axis=2) < 190)
    pix[brown, 3] = 0
    Image.fromarray(pix).save(OUT / "head.png")

    strip = Image.new("L", (128, 256))
    ImageDraw.Draw(strip).rounded_rectangle((21, 1, 107, 255), radius=42, fill=255)
    masked(strip, "neck.png")

    coils = Image.new("L", (680, 390))
    draw = ImageDraw.Draw(coils)
    curves = [
        [(270, 205), (75, 300), (10, 150), (115, 100)],
        [(115, 100), (205, 48), (335, 25), (354, 123)],
        [(354, 123), (375, 230), (215, 302), (180, 226)],
        [(180, 226), (138, 133), (400, 182), (473, 95)],
        [(473, 95), (574, -8), (678, 145), (591, 221)],
        [(591, 221), (529, 295), (392, 340), (361, 246)],
        [(361, 246), (350, 214), (320, 189), (296, 182)],
    ]
    for curve in curves:
        path = bezier(curve)
        draw.line(path, fill=255, width=72, joint="curve")
        for x, y in path:
            draw.ellipse((x-36, y-36, x+36, y+36), fill=255)
    # Tail tapers out of the final coil rather than copying the clipped photo edge.
    tail = bezier([(591, 221), (671, 335), (628, 365), (535, 345)])
    for i in range(len(tail)-1):
        radius = max(2, 27*(1-i/len(tail)))
        x, y = tail[i]
        draw.ellipse((x-radius, y-radius, x+radius, y+radius), fill=255)
    masked(coils, "coils.png")
    manifest = {
        "source": "snake-reference.jpg",
        "sha256": hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
        "method": "painted head contour; sampled white scale texture; reconstructed articulated neck, coils and tapered tail",
        "reference_canvas": [922, 2048],
        "head_contour": head_points,
        "runtime_parts": ["head.png", "neck.png", "coils.png"],
        "background_removed": ["phone UI", "brown support", "flowers", "branches", "red seal"],
    }
    (OUT / "snake-assets.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
    for name in manifest["runtime_parts"]:
        image = Image.open(OUT / name)
        alpha = np.asarray(image.getchannel("A"))
        assert image.mode == "RGBA" and alpha.min() == 0 and alpha.max() == 255
        print(name, image.size, "alpha checked")


if __name__ == "__main__":
    main()
