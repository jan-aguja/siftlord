"""Builds the app icon, Android adaptive foreground and splash logo from the
artwork in assets/icon/siftlord_icon_source.png (1254x1254, a rounded tile on
black with a red glow border).

Run from the repo root:  python3 -I tool/make_icons.py
then:                    dart run flutter_launcher_icons && dart run flutter_native_splash:create
"""
from PIL import Image, ImageDraw

SRC = 'assets/icon/siftlord_icon_source.png'
src = Image.open(SRC).convert('RGB')

# Inside of the tile, just past its glowing border: full-bleed for the
# platform masks, which round the corners themselves.
inner = src.crop((94, 95, 1154, 1155)).resize((1024, 1024), Image.LANCZOS)
inner.save('assets/icon/siftlord_icon.png')  # no alpha: iOS rejects it

# Android adaptive icons crop to a circle/squircle inside a 66% safe zone, so
# the art sits at 72% on black (the art's own background is near-black).
fg = Image.new('RGBA', (1024, 1024), (0, 0, 0, 255))
art = inner.resize((736, 736), Image.LANCZOS)
fg.paste(art, ((1024 - 736) // 2, (1024 - 736) // 2))
fg.save('assets/icon/siftlord_icon_foreground.png')

# Splash: the tile as drawn, glow and rounded corners included, on
# transparency so it floats on the black launch color.
tile = src.crop((40, 40, 1214, 1214)).resize((768, 768), Image.LANCZOS).convert('RGBA')
mask = Image.new('L', tile.size, 0)
ImageDraw.Draw(mask).rounded_rectangle((8, 8, 760, 760), radius=150, fill=255)
tile.putalpha(mask)
tile.save('assets/icon/splash_logo.png')
print('ok')
