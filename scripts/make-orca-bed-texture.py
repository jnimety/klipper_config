#!/usr/bin/env python3
# Usage: make-orca-bed-texture.py <bed size mm> <out.png>   (square beds; no dependencies beyond the stdlib)
# Recreates PrusaSlicer's Voron "bedtexture_250x250-dark.png" style for a bed of any size:
# dark plate with a slight edge vignette, 10mm grid, brighter 50mm lines, lines fading out near the edges.
import sys, zlib, struct, math
size_mm = float(sys.argv[1]); out = sys.argv[2]
ppmm = 8.5                      # matches the original's 2127px / 250mm
n = round(size_mm * ppmm)
BG_EDGE, BG_IN, MINOR, MAJOR = 51, 55, 160, 195
RADIUS, FADE = 2.5, 55.0         # corner radius / line fade-in distance from the edge (mm)
MINOR_W, MAJOR_W = 1 / ppmm, 2.5 / ppmm   # line widths: 1px / 2.5px, as in the original

def fade(d): t = max(0.0, min(1.0, (d - 4.0) / (FADE - 4.0))); return t * t * (3 - 2 * t)
def edge(v): return min(v, size_mm - v)
lines = [(k * 10.0, (k % 5 == 0)) for k in range(1, int(size_mm // 10) + 1) if k * 10.0 < size_mm - 1]

def line_profile(v):
    """(weight 0..1, peak value) of the nearest grid line at coordinate v, faded by that line's distance from the edge."""
    best = (0.0, 0)
    for pos, major in lines:
        half = (MAJOR_W if major else MINOR_W) / 2
        w = max(0.0, min(1.0, (half - abs(v - pos)) * ppmm + 0.5))  # pixel coverage
        if w > 0: best = max(best, (w * fade(edge(pos)), MAJOR if major else MINOR))
    return best

coords = [(i + 0.5) / ppmm for i in range(n)]
prof = [line_profile(v) for v in coords]
along = [fade(edge(v)) for v in coords]          # a line also fades toward the edges along its own length
vign = [min(1.0, edge(v) / 40.0) for v in coords]

raw = bytearray()
for j in reversed(range(n)):    # PNG rows run top (back of bed, max Y) to bottom (front, Y=0)
    y = coords[j]
    raw.append(0)
    hw, hpeak = prof[j]
    for i, x in enumerate(coords):
        # rounded-corner alpha
        cx, cy = min(max(x, RADIUS), size_mm - RADIUS), min(max(y, RADIUS), size_mm - RADIUS)
        a = max(0.0, min(1.0, (RADIUS - math.hypot(x - cx, y - cy)) * ppmm + 0.5))
        bg = BG_EDGE + (BG_IN - BG_EDGE) * min(vign[i], vign[j])
        vw, vpeak = prof[i]
        v = max(bg, bg + (vpeak - bg) * vw * along[j], bg + (hpeak - bg) * hw * along[i])
        g = int(round(v)); raw += bytes((g, g, g, int(round(a * 255))))
def chunk(t, d): return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', n, n, 8, 6, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(bytes(raw), 9)) + chunk(b'IEND', b'')
open(out, 'wb').write(png); print(out, n, "px")
