#!/usr/bin/env python3

from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "Resources" / "AppIcon-generated.png"
MASTER = ROOT / "Resources" / "AppIcon.png"
ICONSET = ROOT / "Resources" / "AppIcon.iconset"


def main() -> None:
    source = Image.open(SOURCE).convert("RGB")

    # The generated artwork contains a white presentation canvas. Crop to the
    # colored tile, then apply a clean macOS-style rounded mask.
    tile = source.crop((78, 68, 1176, 1176)).resize(
        (824, 824),
        Image.Resampling.LANCZOS,
    )
    mask = Image.new("L", tile.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, tile.width - 1, tile.height - 1),
        radius=166,
        fill=255,
    )

    canvas = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    canvas.alpha_composite(Image.merge("RGBA", (*tile.split(), mask)), (100, 100))
    canvas.save(MASTER)

    ICONSET.mkdir(parents=True, exist_ok=True)
    sizes = {
        "icon_16x16.png": 16,
        "icon_16x16@2x.png": 32,
        "icon_32x32.png": 32,
        "icon_32x32@2x.png": 64,
        "icon_128x128.png": 128,
        "icon_128x128@2x.png": 256,
        "icon_256x256.png": 256,
        "icon_256x256@2x.png": 512,
        "icon_512x512.png": 512,
        "icon_512x512@2x.png": 1024,
    }
    for filename, size in sizes.items():
        canvas.resize((size, size), Image.Resampling.LANCZOS).save(ICONSET / filename)


if __name__ == "__main__":
    main()
