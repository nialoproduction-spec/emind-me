#!/usr/bin/env python3
"""Regenerates Sources/RemindMe/Faces/FaceArt.swift from the design images.

    pip install pillow numpy potracer
    python3 scripts/trace_faces.py

Design/expressions.jpg  -- the 3 x 8 sheet of kaomoji faces (white on black;
                           the two crying faces have brown tear fills)
Design/logo.png         -- the -ω- logo (menu bar icon + app icon)

Each face is upscaled, split into a white line-art mask and a brown tear mask,
traced to smooth vector outlines with potrace, and placed on one shared canvas
anchored at the eye line, so swapping faces in the animation never makes the
eyes jump. The app draws the line art in the theme's text colour and the tears
in brown.
"""
from pathlib import Path
import numpy as np
import potrace
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SHEET = ROOT / "Design" / "expressions.jpg"
LOGO = ROOT / "Design" / "logo.png"
OUT = ROOT / "Sources" / "RemindMe" / "Faces" / "FaceArt.swift"

SCALE = 6                  # upscale before tracing, for smooth curves
PAD = 4                    # original px kept around each crop
CANVAS = (200, 104)        # shared drawing space for every face
CANVAS_ANCHOR = (100, 20)  # where each face's (centre x, eye-top y) lands

# Bounding boxes of the 24 faces on the sheet, in sheet order (row-major).
BOXES = [(60, 86, 193, 108), (297, 86, 431, 138), (524, 86, 657, 148), (62, 202, 190, 237),
         (299, 203, 427, 261), (527, 185, 660, 235), (63, 313, 190, 351), (300, 314, 427, 378),
         (524, 323, 657, 364), (63, 425, 196, 467), (298, 425, 430, 498), (525, 425, 657, 504),
         (61, 563, 177, 602), (306, 547, 422, 597), (539, 540, 701, 606), (66, 650, 177, 698),
         (308, 654, 424, 690), (543, 672, 657, 708), (59, 763, 176, 803), (295, 764, 431, 817),
         (548, 769, 659, 813), (59, 863, 181, 911), (296, 858, 430, 914), (545, 861, 656, 902)]

# Anchor = (horizontal centre, top of the eyes). Default is the box centre/top;
# overridden where brows or the anger mark sit above or beside the eyes.
ANCHOR_OVERRIDES = {14: ((306 + 422) / 2, 556), 15: ((539 + 680) / 2, 556)}

NAMES = ["sleepy", "pout", "tearful", "blank", "tongue", "snout", "smug", "smugKiss", "meh", "owo",
         "surprisedKiss", "wail", "tiny", "grumpy", "annoyed", "squee", "dizzy", "sheepish", "sly", "sob",
         "happy", "unimpressed", "furious", "grin"]
LOOKS = ["— ω —", "— 3 —", "— ◠ — (tears)", "● — ●", "◠ ᴥ ◠ (tongue)", "◡ ○ ◡", "◣ ω ◢", "◣ 3 ◢",
         "◒ ᴥ ◒ (tongue)", "O ω O", "O 3 O", "O ∩ O (tears)", "o ᴥ o", "ò ︵ ó", "▭ ▭ ▭ (anger mark)",
         "> ㅅ <", "e ᵐᵐ e", "≡ ᴗ ≡", "◜• ◡ •◝", "T ロ T", "● ▽ ●", "⊖ _ ⊖", "◤ △ ◥", "● ♕ ●"]


def masks_for(rgb):
    a = np.asarray(rgb).astype(int)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    lum = a.mean(axis=2)
    brown = (r > g + 12) & (r > b + 20) & (lum > 35)
    white = (lum > 140) & ~brown
    return white, brown


def trace(mask, offx, offy, scale):
    """Boolean mask -> SVG path data (absolute M/L/C/Z) in original-pixel units."""
    if mask.sum() == 0:
        return None
    # potrace treats dark as ink, so invert: True (ink) -> 0.
    curves = potrace.Bitmap(~mask).trace(turdsize=8, alphamax=1.0, opticurve=True, opttolerance=0.2)
    fmt = lambda v: f"{v:.1f}".rstrip("0").rstrip(".")
    pt = lambda p: f"{fmt(p.x / scale + offx)} {fmt(p.y / scale + offy)}"
    out = []
    for c in curves:
        out.append("M" + pt(c.start_point))
        for s in c.segments:
            if s.is_corner:
                out.append("L" + pt(s.c) + "L" + pt(s.end_point))
            else:
                out.append("C" + pt(s.c1) + " " + pt(s.c2) + " " + pt(s.end_point))
        out.append("Z")
    return "".join(out)


def trace_face(img, box, anchor):
    x0, y0, x1, y1 = box
    crop = img.crop((x0 - PAD, y0 - PAD, x1 + PAD, y1 + PAD))
    big = crop.resize((crop.width * SCALE, crop.height * SCALE), Image.LANCZOS)
    white, brown = masks_for(big)
    offx = (x0 - PAD) - anchor[0] + CANVAS_ANCHOR[0]
    offy = (y0 - PAD) - anchor[1] + CANVAS_ANCHOR[1]
    return trace(white, offx, offy, SCALE), trace(brown, offx, offy, SCALE)


def trace_logo():
    logo = Image.open(LOGO).convert("RGBA")
    bg = Image.new("RGBA", logo.size, (0, 0, 0, 255))
    bg.alpha_composite(logo)
    logo = bg.convert("RGB")
    ink = np.asarray(logo).astype(int).mean(axis=2) > 140
    ys, xs = np.nonzero(ink)
    x0, y0, x1, y1 = xs.min(), ys.min(), xs.max() + 1, ys.max() + 1
    scale = 10
    crop = logo.crop((x0 - 2, y0 - 2, x1 + 2, y1 + 2))
    big = crop.resize((crop.width * scale, crop.height * scale), Image.LANCZOS)
    white, _ = masks_for(big)
    return trace(white, -2, -2, scale), (int(x1 - x0), int(y1 - y0))


def main():
    img = Image.open(SHEET).convert("RGB")
    faces = []
    for i, box in enumerate(BOXES, start=1):
        anchor = ANCHOR_OVERRIDES.get(i, ((box[0] + box[2]) / 2, box[1]))
        faces.append(trace_face(img, box, anchor))
    logo_path, (lw, lh) = trace_logo()

    w, h = CANVAS
    lines = [
        "// GENERATED by scripts/trace_faces.py from Design/expressions.jpg and Design/logo.png.",
        "// Do not edit by hand — re-run the script to change the art.",
        "import CoreGraphics\n",
        "/// The 24 expressions from the expression sheet, in sheet order (left to",
        "/// right, top to bottom), traced to vector outlines. All share one canvas",
        "/// with a common eye line, so swapping faces never makes the eyes jump.",
        "enum Face: Int, CaseIterable {",
    ]
    lines += [f"    case {n} = {i}  // {look}" for i, (n, look) in enumerate(zip(NAMES, LOOKS), start=1)]
    lines += ["}\n", "enum FaceArt {",
              "    /// Shared drawing space for every face, in traced units.",
              f"    static let canvas = CGSize(width: {w}, height: {h})\n",
              "    /// White line art (tinted with the theme's text colour when drawn).",
              "    static func strokesData(_ face: Face) -> String {", "        switch face {"]
    lines += [f'        case .{n}: return "{s}"' for n, (s, _) in zip(NAMES, faces)]
    lines += ["        }", "    }\n",
              "    /// Brown tear fill, drawn underneath the line art. Only the crying faces have it.",
              "    static func tearsData(_ face: Face) -> String? {", "        switch face {"]
    lines += [f'        case .{n}: return "{t}"' for n, (_, t) in zip(NAMES, faces) if t]
    lines += ["        default: return nil", "        }", "    }\n",
              f"    /// The —ω— logo, traced from Design/logo.png. Bounds about {lw} × {lh}.",
              f'    static let logoData = "{logo_path}"', "}"]
    OUT.write_text("\n".join(lines) + "\n")
    print(f"wrote {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
