# terrarium manual: PGM screen dumps (levels 0..15) -> framed RGB PNGs, like the OLED.
# The flora_* dumps become one picture of all the flowers (flora.png), in two columns.
#   python3 tools/manual/topng.py <pgm dir> doc/img
import os, sys, struct, zlib
src, dst = sys.argv[1], sys.argv[2]
os.makedirs(dst, exist_ok=True)
PAL = [(0, 0, 0)] + [tuple(round((l / 15) ** 0.8 * c) for c in (248, 245, 236)) for l in range(1, 16)]
BEZEL, EDGE = (12, 13, 12), (52, 54, 52)

def load(name):
    d = open(os.path.join(src, name + ".pgm"), "rb").read()
    px = d[d.index(b"15\n") + 3:]
    return [list(px[y * 128:(y + 1) * 128]) for y in range(64)]

def png(path, rows):
    h, w = len(rows), len(rows[0])
    raw = b"".join(b"\0" + bytes(c for p in r for c in p) for r in rows)
    ch = lambda t, b: struct.pack(">I", len(b)) + t + b + struct.pack(">I", zlib.crc32(t + b))
    open(path, "wb").write(b"\x89PNG\r\n\x1a\n" + ch(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                           + ch(b"IDAT", zlib.compress(raw, 9)) + ch(b"IEND", b""))

def framed(screen, k=4, pad=14):
    w, h = len(screen[0]) * k, len(screen) * k
    W, H = w + 2 * pad, h + 2 * pad
    out = []
    for y in range(H):
        row = []
        for x in range(W):
            inside = pad <= x < pad + w and pad <= y < pad + h
            if inside:
                row.append(PAL[screen[(y - pad) // k][(x - pad) // k]])
            elif x in (0, W - 1) or y in (0, H - 1):
                row.append(EDGE)
            else:
                row.append(BEZEL)
        out.append(row)
    return out

for f in sorted(os.listdir(src)):
    if f.endswith(".pgm") and not f.startswith("flora_"):
        png(os.path.join(dst, f[:-4] + ".png"), framed(load(f[:-4])))

# the flowers: the bottom of each flora's screen, in two columns
floras = sorted(f[:-4] for f in os.listdir(src) if f.startswith("flora_"))
crops = [load(name)[30:64] for name in floras]
if len(crops) % 2: crops.append([[0] * 128 for _ in range(34)])
strip = []
for i in range(0, len(crops), 2):
    left, right = crops[i], crops[i + 1]
    strip += [left[y] + [0] * 4 + right[y] for y in range(34)]
    if i + 2 < len(crops): strip += [[0] * 260] * 3
if floras: png(os.path.join(dst, "flora.png"), framed(strip, k=3, pad=10))
print(len(os.listdir(dst)), "images")
