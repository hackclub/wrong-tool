# Clippy acting out each mood in his Slack messages (Nudge::Copy::MOODS, plus dramatic), as GIFs Slack can show:
# public/clippy/<mood>.gif, played from his sprite sheet and animations (app/javascript/mascot). Needs Pillow.
#
#   python3 script/clippy_gifs.py
import json, re
from PIL import Image
src, out = "app/assets/images/mascot/clippy.webp", "public/clippy"
js = open("app/javascript/mascot/clippy_animations.js").read()
cols = int(re.search(r"COLUMNS = (\d+)", js).group(1))
anims = {m.group(1): json.loads(m.group(2)) for m in re.finditer(r"^  (\w+): (\[.*\]),?$", js, re.M)}
sheet = Image.open(src).convert("RGBA")
W, H = 124, 93
BG = (255, 248, 214, 255)  # Clippy's old tooltip yellow
def frame(i):
    x, y = i % cols * W, i // cols * H
    tile = Image.new("RGBA", (W, W), BG)
    tile.alpha_composite(sheet.crop((x, y, x + W, y + H)), (0, (W - H) // 2))
    return tile.resize((W * 2, W * 2), Image.NEAREST).convert("RGB")
def render(name, mood):
    steps = [s for s in anims[name] if s.get("frame") is not None]
    frames = [frame(s["frame"]) for s in steps]
    durs = [max(s["duration"], 20) for s in steps]
    durs[-1] += 2500  # hold before looping
    rest = anims["RestPose"][0]["frame"]
    frames.insert(0, frame(rest)); durs.insert(0, 600)
    frames[0].save(f"{out}/{mood}.gif", save_all=True, append_images=frames[1:], duration=durs, loop=0, optimize=True)
MOODS = { "hopeful": "Wave", "proud": "Congratulate", "excited": "GetAttention", "emotional": "LookUp", "dramatic": "LookDown" }
for mood, name in MOODS.items():
    render(name, mood)
