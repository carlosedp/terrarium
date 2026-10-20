# terrarium's mark (make logo), on a 32x32 pixel grid: a jar with an amber lid, OLED black inside, and the
# scene in it (rain, a flower on the grass, its reflection in the pond). Writes icon.svg (the
# mark), logo.svg (the mark and the word) and icon-touch.svg (on a tile, for home screens).
import sys

PAL = {
    "k": "#1d221f",                    # outer outline: holds the shape on light backgrounds
    "G": "#c9d0ca",                    # glass edge: holds it on dark ones
    "B": "#050706",                    # inside: OLED black
    "L": "#d9a441", "l": "#a8741a", "h": "#f0c96e",  # lid, its shade, its highlight
    "w": "#f2f4ef", "m": "#a3aca5", "d": "#525a54",  # pixels: bright, mid, dim
    "g": "#7d857f",                    # the glass's glint
    "A": "#eab54d", "a": "#8f6316",    # the flower, and its reflection
}
N = 32
px = [["."] * N for _ in range(N)]

# the jar's body as a mask of rows (y: x0..x1), then outline and glass found from its edge
BODY = {6: (9, 22), 7: (7, 24), 8: (5, 26), 9: (4, 27)}
for y in range(10, 27): BODY[y] = (3, 28)
BODY.update({27: (4, 27), 28: (5, 26), 29: (7, 24)})
inside = lambda x, y: y in BODY and BODY[y][0] <= x <= BODY[y][1]
for y in BODY:
    for x in range(BODY[y][0], BODY[y][1] + 1):
        if any(not inside(x + dx, y + dy) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
            px[y][x] = "k"
for y in BODY:
    for x in range(BODY[y][0], BODY[y][1] + 1):
        if px[y][x] == ".":
            near = any(px[y + dy][x + dx] == "k" for dx in (-1, 0, 1) for dy in (-1, 0, 1)
                       if 0 <= y + dy < N and 0 <= x + dx < N)
            px[y][x] = "G" if near else "B"

# the lid: amber, outlined, a highlight along the top and a shade along the bottom
for y in range(1, 6):
    for x in range(7, 25):
        edge = y in (1, 5) or x in (7, 24)
        px[y][x] = "k" if edge else ("h" if y == 2 else ("l" if y == 4 else "L"))

def put(x, y, c): px[y][x] = c

for y in range(11, 17): put(6, y, "g")                         # glint on the glass
for x, y in ((10, 11), (22, 10), (14, 9), (19, 13)):            # rain
    put(x, y, "w"); put(x, y + 1, "m")
# the flower: petals around a bright center, on a stem with a leaf
for x, y in ((16, 13), (14, 15), (18, 15), (16, 17), (15, 14), (17, 14), (15, 16), (17, 16)):
    put(x, y, "A")
put(16, 15, "w"); put(15, 15, "A"); put(17, 15, "A"); put(16, 14, "A"); put(16, 16, "A")
for y in range(18, 23): put(16, y, "m")
put(17, 20, "m"); put(18, 19, "m")
# grass along the ground, the ground line, and the pond under it
for x, h in ((6, 1), (8, 2), (9, 1), (11, 2), (12, 1), (13, 2), (19, 2), (20, 1), (22, 2), (23, 1), (25, 2)):
    for k in range(h): put(x, 22 - k, "d" if k else "m")
for x in range(5, 27): put(x, 23, "m")
for x in list(range(7, 12)) + list(range(20, 25)): put(x, 25, "d")
put(16, 25, "a"); put(16, 26, "a"); put(15, 25, "a"); put(17, 25, "a")   # the flower, reflected

def rects(grid, ox=0, oy=0, scale=1, cls=None):
    out = []
    for y, row in enumerate(grid):
        x = 0
        while x < len(row):
            c = row[x]
            if c in ". ":
                x += 1
                continue
            x0 = x
            while x < len(row) and row[x] == c: x += 1
            fill = f'class="{cls}"' if cls else f'fill="{PAL[c]}"'
            out.append(f'<rect x="{ox + x0 * scale}" y="{oy + y * scale}" width="{(x - x0) * scale}" '
                       f'height="{scale}" {fill}/>')
    return out

HEAD = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="{vb}" shape-rendering="crispEdges">'
out = sys.argv[1]
grid = ["".join(r) for r in px]
open(out + "/icon.svg", "w").write("\n".join(
    [HEAD.format(vb=f"0 0 {N} {N}"), "<title>terrarium</title>"] + rects(grid) + ["</svg>"]) + "\n")

# for a phone's home screen: the mark on a dark tile (iOS fills transparency with black anyway);
# 36 units, so a 180 px PNG is exactly 5 px a pixel
open(out + "/icon-touch.svg", "w").write("\n".join(
    [HEAD.format(vb="-2 -2 36 36"), '<rect x="-2" y="-2" width="36" height="36" fill="#121513"/>']
    + rects(grid) + ["</svg>"]) + "\n")

# the word, in a small pixel face: x-height 5, t and i reaching up 2
GLYPHS = {
    "t": [".x.", ".x.", "xxx", ".x.", ".x.", ".x.", "..x"],
    "e": ["....", "....", ".xx.", "x..x", "xxxx", "x...", ".xxx"],
    "r": ["...", "...", "x.x", "xx.", "x..", "x..", "x.."],
    "a": ["....", "....", ".xx.", "...x", ".xxx", "x..x", ".xxx"],
    "i": ["x", ".", "x", "x", "x", "x", "x"],
    "u": ["....", "....", "x..x", "x..x", "x..x", "x..x", ".xxx"],
    "m": [".....", ".....", "xx.x.", "x.x.x", "x.x.x", "x.x.x", "x.x.x"],
}
word = [""] * 7
for i, ch in enumerate("terrarium"):
    for r in range(7): word[r] += ("." if i else "") + GLYPHS[ch][r]
S = 3                                   # a letter pixel is 3 of the mark's
wx, wy = N + 9, (N - 7 * S) // 2 + 2    # sits on the mark's ground, give or take
W = wx + len(word[0]) * S + 1
style = ('<style>.ink{fill:#1b1f1c}@media (prefers-color-scheme:dark){.ink{fill:#e3e6e1}}</style>')
open(out + "/logo.svg", "w").write("\n".join(
    [HEAD.format(vb=f"0 0 {W} {N}"), "<title>terrarium</title>", style] + rects(grid)
    + rects(word, wx, wy, S, "ink") + ["</svg>"]) + "\n")
print("wrote icon.svg, icon-touch.svg, logo.svg; logo is", W, "x", N)
