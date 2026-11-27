from PIL import Image, ImageDraw, ImageFont

FONT_PATH = "JetBrainsMono-Medium.ttf"
CELL_W, CELL_H = 8, 14
COLS, ROWS = 16, 16          # 256 glyphs, code point = row*16 + col
FONT_SIZE = 12               # tune this (see notes)

font = ImageFont.truetype(FONT_PATH, FONT_SIZE)
atlas = Image.new("L", (COLS * CELL_W, ROWS * CELL_H), 0)   # black bg, 8-bit gray
draw = ImageDraw.Draw(atlas)

# Vertical placement: use the font's ascent so all glyphs share a baseline
ascent, descent = font.getmetrics()
baseline_y = (CELL_H - (ascent + descent)) // 2 + ascent

for code in range(32, 256):
    ch = bytes([code]).decode("cp1252", errors="replace")   # or "latin-1"
    col, row = code % COLS, code // COLS
    x0, y0 = col * CELL_W, row * CELL_H
    # center horizontally using the advance width, anchor "ls" = left/baseline
    adv = font.getlength(ch)
    x = x0 + (CELL_W - adv) / 2
    draw.text((x, y0 + baseline_y), ch, font=font, fill=255, anchor="ls")

alpha = atlas
rgba = Image.new("RGBA", atlas.size, (255, 255, 255, 0))
rgba.putalpha(alpha)
rgba.save("font.png")
