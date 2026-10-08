# Clippy acting out each mood (Nudge::Copy::MOODS, plus dramatic) as Slack emoji: tmp/clippy_emoji/clippy-<mood>.gif,
# 128x128 on a transparent background and under Slack's 128KB, from the same animations as script/clippy_gifs.py.
# Add them in #emojibot: a message with the emoji name and the GIF attached. Needs Pillow.
#
#   python3 script/clippy_emoji.py
import json, os, re
from PIL import Image
src, out = "app/assets/images/mascot/clippy.webp", "tmp/clippy_emoji"
LIMIT = 128 * 1024
js = open("app/javascript/mascot/clippy_animations.js").read()
cols = int(re.search(r"COLUMNS = (\d+)", js).group(1))
anims = {m.group(1): json.loads(m.group(2)) for m in re.finditer(r"^  (\w+): (\[.*\]),?$", js, re.M)}
sheet = Image.open(src).convert("RGBA")
W, H = 124, 93
def frame(i, colors):
    x, y = i % cols * W, i // cols * H
    tile = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    tile.alpha_composite(sheet.crop((x, y, x + W, y + H)), (0, (W - H) // 2))
    tile = tile.resize((128, 128), Image.LANCZOS)
    # GIF transparency is all or nothing: anything mostly see-through goes, the rest gets Clippy's palette.
    alpha = tile.getchannel("A").point(lambda a: 255 if a > 96 else 0)
    quantized = tile.convert("RGB").quantize(colors - 1, method=Image.Quantize.MEDIANCUT)
    palette = quantized.getpalette()[: 3 * (colors - 1)] + [255, 0, 255]
    quantized.putpalette(palette)
    quantized.paste(colors - 1, mask=alpha.point(lambda a: 255 - a))
    quantized.info["transparency"] = colors - 1
    return quantized
def render(name, mood):
    steps = [s for s in anims[name] if s.get("frame") is not None]
    rest = anims["RestPose"][0]["frame"]
    for colors, every in [(64, 1), (32, 1), (32, 2), (16, 2), (16, 3)]:  # until it fits
        kept = steps[::every]
        frames = [frame(rest, colors)] + [frame(s["frame"], colors) for s in kept]
        durs = [600] + [max(s["duration"] * every, 20) for s in kept]
        durs[-1] += 2500  # hold before looping
        path = f"{out}/clippy-{mood}.gif"
        frames[0].save(path, save_all=True, append_images=frames[1:], duration=durs, loop=0, disposal=2,
                       transparency=colors - 1, optimize=False)
        if os.path.getsize(path) <= LIMIT:
            return print(f"{path}: {os.path.getsize(path) // 1024}KB, {len(frames)} frames, {colors} colors")
    raise SystemExit(f"{mood} won't fit under {LIMIT // 1024}KB")
os.makedirs(out, exist_ok=True)
MOODS = { "hopeful": "Wave", "proud": "Congratulate", "excited": "GetAttention", "emotional": "LookUp", "dramatic": "LookDown" }
for mood, name in MOODS.items():
    render(name, mood)
