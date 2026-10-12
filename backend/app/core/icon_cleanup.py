"""Cleans uploaded icons (seasons, ranks, achievements) so they sit nicely on
the app's plates.

Images made by AI generators usually claim "transparent background" but come
with a solid one (black, white, any flat colour), often as JPEG, plus wide
empty margins. Shown as-is, the app draws a dark square and a tiny picture.
`clean_icon` turns the flat background into real transparency -- filling only
from the image edges, so dark details INSIDE the picture stay -- trims the
empty margins, centres the picture in a square and saves a 512px PNG. Any
failure returns None and the caller keeps the original upload.
"""

import io

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageStat

SIZE = 512
# How far (per channel) a pixel may differ from the edge colour and still be
# background: catches the dark vignette/glow of generated images, keeps the art.
THRESHOLD = 60
_MARK = (255, 0, 255)


def _has_real_transparency(img: Image.Image) -> bool:
    if img.mode not in ("RGBA", "LA") and "transparency" not in img.info:
        return False
    alpha = img.convert("RGBA").getchannel("A")
    return alpha.getextrema()[0] < 250


def _border_is_flat(rgb: Image.Image) -> bool:
    w, h = rgb.size
    k = max(2, min(w, h) // 50)
    strips = [rgb.crop((0, 0, w, k)), rgb.crop((0, h - k, w, h)), rgb.crop((0, 0, k, h)), rgb.crop((w - k, 0, w, h))]
    return all(max(ImageStat.Stat(s).stddev) < 40 for s in strips)


def _background_to_alpha(rgb: Image.Image) -> Image.Image:
    filled = rgb.copy()
    w, h = rgb.size
    step = max(1, min(w, h) // 16)
    seeds = [(x, 0) for x in range(0, w, step)] + [(x, h - 1) for x in range(0, w, step)]
    seeds += [(0, y) for y in range(0, h, step)] + [(w - 1, y) for y in range(0, h, step)]
    for seed in seeds:
        if filled.getpixel(seed) != _MARK:
            ImageDraw.floodfill(filled, seed, _MARK, thresh=THRESHOLD)
    # Background = pixels the fill turned into the marker colour.
    diff = ImageChops.difference(filled, Image.new("RGB", rgb.size, _MARK)).convert("L")
    background = diff.point(lambda v: 255 if v < 3 else 0)
    # Plus big enclosed pockets of exactly the background colour (the black
    # inside a ring or between arms) -- big ones only, so dark details like
    # eyes or outlines stay.
    edge = rgb.crop((0, 0, w, max(2, h // 50)))
    bg_color = tuple(int(c) for c in ImageStat.Stat(edge).median)
    near = ImageChops.difference(rgb, Image.new("RGB", rgb.size, bg_color)).convert("L").point(lambda v: 255 if v < 20 else 0)
    pockets = ImageChops.subtract(near, background)
    # Only for the plain black/white backdrops generators use; a coloured
    # backdrop may share its colour with the art itself.
    plain = max(bg_color) < 40 or min(bg_color) > 215
    label, sizes = _blobs(pockets) if plain else ([], {})
    big = {lab for lab, size in sizes.items() if size >= 0.005 * 128 * 128}
    if big:
        extra = Image.new("L", (128, 128))
        extra.putdata([255 if lab in big else 0 for lab in label])
        extra = ImageChops.multiply(extra.resize(rgb.size, Image.BILINEAR), near)
        background = ImageChops.lighter(background, extra)
    # Shrink by ~2px first: the anti-aliased rim keeps the old background's
    # colour (a dark halo on black), then soften the edge.
    alpha = ImageChops.invert(background).filter(ImageFilter.MinFilter(5)).filter(ImageFilter.GaussianBlur(1.2))
    out = rgb.convert("RGBA")
    out.putalpha(alpha)
    return out


def _blobs(mask: Image.Image, n: int = 128) -> tuple[list[int], dict[int, int]]:
    """Connected components of a binary mask, on an n×n copy: (labels, sizes)."""
    px = list(mask.resize((n, n), Image.BILINEAR).point(lambda v: 1 if v > 127 else 0).getdata())
    label = [0] * (n * n)
    sizes: dict[int, int] = {}
    current = 0
    for start in range(n * n):
        if not px[start] or label[start]:
            continue
        current += 1
        stack = [start]
        label[start] = current
        count = 0
        while stack:
            i = stack.pop()
            count += 1
            x, y = i % n, i // n
            for j in (i - 1 if x else -1, i + 1 if x < n - 1 else -1, i - n if y else -1, i + n if y < n - 1 else -1):
                if j >= 0 and px[j] and not label[j]:
                    label[j] = current
                    stack.append(j)
        sizes[current] = count
    return label, sizes


def _keep_main_shapes(rgba: Image.Image) -> Image.Image:
    """Drops small detached bits far from the main picture (watermarks, captions,
    stray dots) so they don't widen the crop. Works on a 128px copy of the
    mask: keeps every blob at least 4% the size of the largest one."""
    alpha = rgba.getchannel("A")
    n = 128
    label, sizes = _blobs(alpha.point(lambda v: 255 if v > 40 else 0), n)
    if len(sizes) <= 1:
        return rgba
    keep_min = max(sizes.values()) * 0.04
    keep = Image.new("L", (n, n))
    keep.putdata([255 if lab and sizes[lab] >= keep_min else 0 for lab in label])
    keep = keep.filter(ImageFilter.MaxFilter(5)).resize(rgba.size, Image.BILINEAR)
    out = rgba.copy()
    out.putalpha(ImageChops.multiply(alpha, keep))
    return out


def clean_icon(data: bytes) -> bytes | None:
    try:
        img = Image.open(io.BytesIO(data))
        img.load()
        if _has_real_transparency(img):
            rgba = img.convert("RGBA")
        else:
            rgb = img.convert("RGB")
            if not _border_is_flat(rgb):
                return None  # a full picture (photo, scene): leave it alone
            rgba = _background_to_alpha(rgb)
        rgba = _keep_main_shapes(rgba)
        bbox = rgba.getchannel("A").point(lambda v: 255 if v > 24 else 0).getbbox()
        if bbox is None:
            return None
        art = rgba.crop(bbox)
        side = int(max(art.size) * 1.06)
        canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
        canvas.paste(art, ((side - art.width) // 2, (side - art.height) // 2), art)
        canvas = canvas.resize((SIZE, SIZE), Image.LANCZOS)
        buf = io.BytesIO()
        canvas.save(buf, format="PNG", optimize=True)
        return buf.getvalue()
    except Exception:  # noqa: BLE001 -- an icon must never break an upload
        return None
