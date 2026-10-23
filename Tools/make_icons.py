#!/usr/bin/env python3
"""Renders every icon from Support/logo.svg (needs ImageMagick with SVG support).

Usage: python3 Tools/make_icons.py
"""

import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LOGO = (ROOT / "Support" / "logo.svg").read_text()
BACKGROUND = '<rect id="background" width="1024" height="1024" fill="url(#bg)"/>'


def render(svg: str, size: int, out: Path) -> None:
    with tempfile.NamedTemporaryFile("w", suffix=".svg") as tmp:
        tmp.write(svg)
        tmp.flush()
        subprocess.run(
            ["magick", "-background", "none", "-density", "300", tmp.name, "-resize", f"{size}x{size}", f"PNG32:{out}"],
            check=True,
        )


def main() -> None:
    images = ROOT / "WebExtension" / "images"
    images.mkdir(parents=True, exist_ok=True)

    # App icon: square and opaque, iOS rounds the corners itself.
    render(LOGO, 1024, ROOT / "Support" / "AppIcon.png")

    # Web extension icons: rounded square.
    rounded = LOGO.replace(BACKGROUND, BACKGROUND.replace("<rect ", '<rect rx="230" '))
    for size in (48, 96, 128, 256, 512):
        render(rounded, size, images / f"icon-{size}.png")

    # Logo shown inside the app and popup: just the bird on transparent.
    bird_only = LOGO.replace(BACKGROUND, "")
    render(bird_only, 512, ROOT / "Support" / "KiviLogo.png")
    render(bird_only, 128, images / "kivi.png")

    # Safari toolbar icon: black silhouette, Safari tints it.
    silhouette = bird_only.replace("url(#kiwi)", "#000").replace('fill="#0f0f11"', 'fill="#fff" fill-opacity="0"')
    for size in (16, 32):
        render(silhouette, size, images / f"toolbar-{size}.png")

    print("Icons written.")


if __name__ == "__main__":
    main()
