#!/usr/bin/env python3
"""Burn captions onto captured demo frames.

This ffmpeg build ships without drawtext (no libfreetype), so captions are
rendered with PIL instead and the frames are handed to ffmpeg already
composited.

Reads /tmp/bsframes/script.tsv (id, seconds, caption), writes cap-NN.png and
concat.txt beside it.
"""

import pathlib
import sys

from PIL import Image, ImageDraw, ImageFont

FRAMES = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "/tmp/bsframes")
CANVAS = (1600, 1000)
BAR_H = 104
BG = (7, 10, 20)
INK = (230, 230, 230)
ACCENT = (57, 135, 229)

FONT_CANDIDATES = [
    ("/System/Library/Fonts/Supplemental/Menlo.ttc", 0),
    ("/System/Library/Fonts/Menlo.ttc", 0),
    ("/System/Library/Fonts/Supplemental/Courier New.ttf", None),
    ("/System/Library/Fonts/Helvetica.ttc", 0),
]


def load_font(size: int):
    for path, index in FONT_CANDIDATES:
        p = pathlib.Path(path)
        if not p.exists():
            continue
        try:
            if index is None:
                return ImageFont.truetype(str(p), size)
            return ImageFont.truetype(str(p), size, index=index)
        except Exception:
            continue
    return ImageFont.load_default()


def wrap(draw, text: str, font, max_w: int) -> list:
    words, lines, cur = text.split(), [], ""
    for w in words:
        trial = f"{cur} {w}".strip()
        if draw.textlength(trial, font=font) <= max_w:
            cur = trial
        else:
            if cur:
                lines.append(cur)
            cur = w
    if cur:
        lines.append(cur)
    return lines[:2]


def main() -> None:
    tsv = FRAMES / "script.tsv"
    if not tsv.exists():
        raise SystemExit(f"missing {tsv}")

    font = load_font(29)
    concat = []

    for line in tsv.read_text().splitlines():
        if not line.strip():
            continue
        fid, secs, caption = line.split("\t", 2)
        src = FRAMES / f"frame-{fid}.png"
        if not src.exists():
            continue

        shot = Image.open(src).convert("RGB")
        # Fit the shot into the frame above the caption bar, preserving aspect.
        avail = (CANVAS[0], CANVAS[1] - BAR_H)
        scale = min(avail[0] / shot.width, avail[1] / shot.height)
        shot = shot.resize(
            (max(1, int(shot.width * scale)), max(1, int(shot.height * scale))),
            Image.LANCZOS,
        )

        canvas = Image.new("RGB", CANVAS, BG)
        canvas.paste(shot, ((CANVAS[0] - shot.width) // 2, 0))

        draw = ImageDraw.Draw(canvas)
        top = CANVAS[1] - BAR_H
        draw.rectangle([0, top, CANVAS[0], CANVAS[1]], fill=BG)
        draw.rectangle([0, top, CANVAS[0], top + 2], fill=ACCENT)

        lines = wrap(draw, caption, font, CANVAS[0] - 96)
        y = top + (BAR_H - (len(lines) * 36)) // 2 + 2
        for ln in lines:
            draw.text((48, y), ln, font=font, fill=INK)
            y += 36

        out = FRAMES / f"cap-{fid}.png"
        canvas.save(out)
        concat.append(f"file '{out}'\nduration {secs}")
        print(f"  captioned {fid} ({secs}s)")

    if not concat:
        raise SystemExit("no frames captioned")

    # concat demuxer needs the final file repeated for its duration to apply
    last = concat[-1].split("\n")[0]
    (FRAMES / "concat.txt").write_text("\n".join(concat) + "\n" + last + "\n")
    print(f"wrote {FRAMES / 'concat.txt'}")


if __name__ == "__main__":
    main()
