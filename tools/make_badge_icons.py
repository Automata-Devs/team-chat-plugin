"""
Makes the Team Chat toolbar icon with an unread badge: the base icon with a
red circle (a pill for "9+") in the top-right corner, outlined in black like
the icon, and a bold white count. Pure Python (zlib + struct): PNG in/out and
a small TrueType reader for the digits.

Usage (from the repository root):
    python -I tools/make_badge_icons.py <base.png> <font.ttf> <out dir> [labels...]

base.png is the toolbar icon (420x420 RGBA, from the thumbnails API for
Config/ToolbarIcons.BASE); the font is a bold TrueType one (Segoe UI Bold:
C:/Windows/Fonts/segoeuib.ttf). Upload the images and put their IDs in
src/Config/ToolbarIcons.luau.
"""

import os
import struct
import sys
import zlib

RED = (247, 75, 82)  # Theme danger: the chat's unread badge
BLACK = (0, 0, 0)
WHITE = (255, 255, 255)


# ---------------------------------------------------------------- PNG

def read_png(path):
    data = open(path, "rb").read()
    assert data[:8] == b"\x89PNG\r\n\x1a\n"
    pos, idat, width, height = 8, b"", 0, 0
    while pos < len(data):
        length, kind = struct.unpack(">I4s", data[pos:pos + 8])
        chunk = data[pos + 8:pos + 8 + length]
        if kind == b"IHDR":
            width, height, depth, ctype, _, _, interlace = struct.unpack(">IIBBBBB", chunk)
            assert depth == 8 and ctype == 6 and interlace == 0, "needs 8-bit RGBA"
        elif kind == b"IDAT":
            idat += chunk
        pos += 12 + length
    raw = zlib.decompress(idat)
    stride, bpp = width * 4, 4
    pixels, prev = [], bytearray(stride)
    for y in range(height):
        f = raw[y * (stride + 1)]
        line = bytearray(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
        for i in range(stride):
            a = line[i - bpp] if i >= bpp else 0
            b = prev[i]
            c = prev[i - bpp] if i >= bpp else 0
            if f == 1:
                line[i] = (line[i] + a) & 255
            elif f == 2:
                line[i] = (line[i] + b) & 255
            elif f == 3:
                line[i] = (line[i] + (a + b) // 2) & 255
            elif f == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pred = a if pa <= pb and pa <= pc else (b if pb <= pc else c)
                line[i] = (line[i] + pred) & 255
        pixels.append([[line[x * 4 + k] / 255 for k in range(4)] for x in range(width)])
        prev = line
    return pixels


def write_png(path, pixels):
    height, width = len(pixels), len(pixels[0])
    raw = bytearray()
    for row in pixels:
        raw.append(0)
        for px in row:
            raw += bytes(max(0, min(255, round(v * 255))) for v in px)

    def chunk(kind, body):
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF)

    out = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
    out += chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b"")
    open(path, "wb").write(out)


def over(pixel, color, coverage):
    """Paints `color` at `coverage` (0-1) over a straight-alpha pixel."""
    if coverage <= 0:
        return
    a = pixel[3]
    out_a = coverage + a * (1 - coverage)
    if out_a <= 0:
        return
    for k, src in enumerate(color):
        pixel[k] = (src / 255 * coverage + pixel[k] * a * (1 - coverage)) / out_a
    pixel[3] = out_a


# ---------------------------------------------------------- TrueType

class Font:
    def __init__(self, path):
        self.data = open(path, "rb").read()
        num = struct.unpack(">H", self.data[4:6])[0]
        self.tables = {}
        for i in range(num):
            tag, _, offset, length = struct.unpack(">4sIII", self.data[12 + i * 16:28 + i * 16])
            self.tables[tag.decode("latin-1")] = (offset, length)
        head = self.tables["head"][0]
        self.long_loca = struct.unpack(">h", self.data[head + 50:head + 52])[0] == 1
        hhea = self.tables["hhea"][0]
        self.num_metrics = self._u16(hhea + 34)
        self.cmap = self._cmap()

    def _u16(self, at):
        return struct.unpack(">H", self.data[at:at + 2])[0]

    def _cmap(self):
        base = self.tables["cmap"][0]
        for i in range(self._u16(base + 2)):
            platform, encoding, offset = struct.unpack(">HHI", self.data[base + 4 + i * 8:base + 12 + i * 8])
            sub = base + offset
            if self._u16(sub) == 4 and platform == 3 and encoding in (1, 10):
                mapping = {}
                segs = self._u16(sub + 6) // 2
                ends = sub + 14
                starts = ends + segs * 2 + 2
                deltas = starts + segs * 2
                ranges = deltas + segs * 2
                for s in range(segs):
                    end, start = self._u16(ends + s * 2), self._u16(starts + s * 2)
                    delta = struct.unpack(">h", self.data[deltas + s * 2:deltas + s * 2 + 2])[0]
                    roff = self._u16(ranges + s * 2)
                    for code in range(start, min(end, 0x7F) + 1):
                        if roff == 0:
                            glyph = (code + delta) & 0xFFFF
                        else:
                            glyph = self._u16(ranges + s * 2 + roff + (code - start) * 2)
                            glyph = (glyph + delta) & 0xFFFF if glyph else 0
                        mapping[chr(code)] = glyph
                return mapping
        raise ValueError("no unicode cmap")

    def advance(self, glyph):
        hmtx = self.tables["hmtx"][0]
        return self._u16(hmtx + min(glyph, self.num_metrics - 1) * 4)

    def contours(self, glyph):
        """The glyph's outline: contours of (x, y, on_curve) in font units."""
        loca = self.tables["loca"][0]
        if self.long_loca:
            start, end = struct.unpack(">II", self.data[loca + glyph * 4:loca + glyph * 4 + 8])
        else:
            start, end = (v * 2 for v in struct.unpack(">HH", self.data[loca + glyph * 2:loca + glyph * 2 + 4]))
        if start == end:
            return []
        at = self.tables["glyf"][0] + start
        count = struct.unpack(">h", self.data[at:at + 2])[0]
        assert count >= 0, "composite glyphs aren't needed for digits"
        ends = [self._u16(at + 10 + i * 2) for i in range(count)]
        points = ends[-1] + 1
        p = at + 10 + count * 2
        p += 2 + self._u16(p)  # skip the instructions
        flags = []
        while len(flags) < points:
            f = self.data[p]
            p += 1
            flags.append(f)
            if f & 8:
                flags.extend([f] * self.data[p])
                p += 1
        coords = []
        for short, same in ((2, 16), (4, 32)):
            value, values = 0, []
            for f in flags:
                if f & short:
                    d = self.data[p]
                    p += 1
                    value += d if f & same else -d
                elif not f & same:
                    value += struct.unpack(">h", self.data[p:p + 2])[0]
                    p += 2
                values.append(value)
            coords.append(values)
        result, first = [], 0
        for end in ends:
            result.append([(coords[0][i], coords[1][i], bool(flags[i] & 1)) for i in range(first, end + 1)])
            first = end + 1
        return result


def flatten(contour, steps=12):
    """A TrueType contour (quadratic, with implied on-curve points) as a polygon."""
    pts = list(contour)
    expanded = []
    for i, p in enumerate(pts):
        expanded.append(p)
        nxt = pts[(i + 1) % len(pts)]
        if not p[2] and not nxt[2]:
            expanded.append(((p[0] + nxt[0]) / 2, (p[1] + nxt[1]) / 2, True))
    while not expanded[0][2]:
        expanded = expanded[1:] + expanded[:1]
    out = []
    n = len(expanded)
    i = 0
    while i < n:
        p = expanded[i]
        nxt = expanded[(i + 1) % n]
        if nxt[2]:
            out.append((p[0], p[1]))
            i += 1
        else:
            end = expanded[(i + 2) % n]
            for s in range(steps):
                t = s / steps
                out.append((
                    (1 - t) ** 2 * p[0] + 2 * (1 - t) * t * nxt[0] + t * t * end[0],
                    (1 - t) ** 2 * p[1] + 2 * (1 - t) * t * nxt[1] + t * t * end[1],
                ))
            i += 2
    return out


def text_polygons(font, text, height, center):
    """Polygons (pixel space, y down) for `text`, its digits `height` px tall,
    the ink's bounding box centered on `center`. Also returns its width."""
    zero = [p for c in font.contours(font.cmap["0"]) for p in c]
    scale = height / max(p[1] for p in zero)
    polys, pen = [], 0
    for ch in text:
        glyph = font.cmap[ch]
        for contour in font.contours(glyph):
            polys.append([((x + pen) * scale, -y * scale) for x, y in flatten(contour)])
        pen += font.advance(glyph)
    xs = [x for poly in polys for x, _ in poly]
    ys = [y for poly in polys for _, y in poly]
    dx = center[0] - (min(xs) + max(xs)) / 2
    dy = center[1] - (min(ys) + max(ys)) / 2
    return [[(x + dx, y + dy) for x, y in poly] for poly in polys], max(xs) - min(xs)


def fill_polygons(pixels, polys, color, rows_per_pixel=4):
    """Nonzero fill: exact horizontal coverage, `rows_per_pixel` sub-rows."""
    height, width = len(pixels), len(pixels[0])
    edges = []
    for poly in polys:
        for i in range(len(poly)):
            (x0, y0), (x1, y1) = poly[i], poly[(i + 1) % len(poly)]
            if y0 != y1:
                edges.append((x0, y0, x1, y1, 1 if y1 > y0 else -1))
    ys = [y for poly in polys for _, y in poly]
    for py in range(max(0, int(min(ys))), min(height - 1, int(max(ys)) + 1) + 1):
        cover = {}
        for k in range(rows_per_pixel):
            sy = py + (k + 0.5) / rows_per_pixel
            hits = []
            for x0, y0, x1, y1, w in edges:
                lo, hi = (y0, y1) if y0 < y1 else (y1, y0)
                if lo <= sy < hi:
                    hits.append((x0 + (sy - y0) * (x1 - x0) / (y1 - y0), w))
            hits.sort()
            winding = 0
            for j in range(len(hits) - 1):
                winding += hits[j][1]
                if winding != 0:
                    a, b = hits[j][0], hits[j + 1][0]
                    for px in range(max(0, int(a)), min(width - 1, int(b)) + 1):
                        overlap = min(b, px + 1) - max(a, px)
                        if overlap > 0:
                            cover[px] = cover.get(px, 0) + overlap / rows_per_pixel
        for px, amount in cover.items():
            over(pixels[py][px], color, min(1.0, amount))


def fill_pill(pixels, left, top, right, bottom, color, samples=4):
    """A rectangle with half-circle ends (a circle when it's square)."""
    radius = (bottom - top) / 2
    cy = (top + bottom) / 2
    for py in range(max(0, int(top) - 1), min(len(pixels), int(bottom) + 2)):
        for px in range(max(0, int(left) - 1), min(len(pixels[0]), int(right) + 2)):
            inside = 0
            for sy in range(samples):
                y = py + (sy + 0.5) / samples
                for sx in range(samples):
                    x = px + (sx + 0.5) / samples
                    cx = min(max(x, left + radius), right - radius)
                    if (x - cx) ** 2 + (y - cy) ** 2 <= radius * radius:
                        inside += 1
            over(pixels[py][px], color, inside / (samples * samples))


def make(base_path, font, label, out_path):
    pixels = read_png(base_path)
    size = len(pixels)
    radius = size * 0.235  # the badge: ~47% of the icon across
    ring = size * 0.034  # as thick as the icon's own black outline
    margin = size * 0.006
    inner = radius - ring
    digit_height = inner * 1.15
    _, text_width = text_polygons(font, label, digit_height, (0, 0))
    inner_width = max(inner * 2, text_width + inner * 0.9)
    right, top = size - margin, margin
    left, bottom = right - inner_width - ring * 2, top + radius * 2
    fill_pill(pixels, left, top, right, bottom, BLACK)
    fill_pill(pixels, left + ring, top + ring, right - ring, bottom - ring, RED)
    polys, _ = text_polygons(font, label, digit_height, ((left + right) / 2, (top + bottom) / 2))
    fill_polygons(pixels, polys, WHITE)
    write_png(out_path, pixels)


def main():
    base_path, font_path, out_dir = sys.argv[1:4]
    os.makedirs(out_dir, exist_ok=True)
    font = Font(font_path)
    labels = sys.argv[4:] or ([str(n) for n in range(1, 10)] + ["9+"])
    for label in labels:
        name = "TeamChatIcon_" + ("9plus" if label == "9+" else label) + ".png"
        make(base_path, font, label, os.path.join(out_dir, name))
        print("made", name)


if __name__ == "__main__":
    main()
