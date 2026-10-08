"""Original deterministic, periodic cotton and wood tiles. Requires Pillow only to rebuild."""
from pathlib import Path
import math
import random
from PIL import Image

ROOT = Path(__file__).resolve().parents[1] / "assets" / "stage"
ROOT.mkdir(parents=True, exist_ok=True)
rng = random.Random(20261008)
size = 512
threads_x = [rng.uniform(-1.7, 1.7) for _ in range(size)]
threads_y = [rng.uniform(-1.7, 1.7) for _ in range(size)]
cotton = Image.new("RGB", (size, size))
wood = Image.new("RGB", (size, size))
for y in range(size):
    for x in range(size):
        weave = 3.0 * math.cos(x * math.tau / 4) + 2.4 * math.cos(y * math.tau / 4)
        weave += 1.5 * math.cos((x + y) * math.tau / 8)
        slow = 2.2 * math.sin(x * math.tau / size) * math.cos(y * math.tau / size)
        value = round(128 + weave + slow + threads_x[x] + threads_y[y] + rng.uniform(-1, 1))
        cotton.putpixel((x, y), (value, value, value))
        bend = 0.5 * math.sin(x * math.tau / size) + 0.18 * math.sin(x * math.tau / 128)
        grain = 9 * math.sin(y * math.tau / 32 + bend) + 3 * math.sin(y * math.tau / 7.5294117647 + bend)
        grain += rng.uniform(-2.5, 2.5)
        wood.putpixel((x, y), tuple(round(v + grain * k) for v, k in [(126, 1), (94, .8), (58, .55)]))
cotton.save(ROOT / "cotton_weave.png")
wood.save(ROOT / "wood_grain.png")
print(f"Generated two original {size}x{size} tiles in {ROOT}")
