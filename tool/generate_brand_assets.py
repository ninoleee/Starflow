from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
BUILD_DIR = ROOT / "build" / "brand_assets"
APP_ICON_SVG = ROOT / "assets" / "branding" / "starflow_icon_master.svg"
TV_BANNER_HTML = ROOT / "docs" / "starflow_tv_banner.html"

APP_ICON_VIEWPORT = (1024, 1024)
APP_ICON_SCALE = 4
APP_ICON_MASTER_SIZE = (
    APP_ICON_VIEWPORT[0] * APP_ICON_SCALE,
    APP_ICON_VIEWPORT[1] * APP_ICON_SCALE,
)

TV_BANNER_VIEWPORT = (1280, 720)
TV_BANNER_SCALE = 3
TV_BANNER_CAPTURE_VIEWPORT = (1280, 815)

APP_ICON_TARGETS: dict[Path, tuple[int, int]] = {
    ROOT / "assets/branding/starflow_launch_logo.png": (512, 512),
    ROOT / "android/app/src/main/res/drawable-nodpi/icon_preview_sharp.png": (1024, 1024),
    ROOT / "android/app/src/main/res/mipmap-mdpi/ic_launcher.png": (48, 48),
    ROOT / "android/app/src/main/res/mipmap-hdpi/ic_launcher.png": (72, 72),
    ROOT / "android/app/src/main/res/mipmap-xhdpi/ic_launcher.png": (96, 96),
    ROOT / "android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png": (144, 144),
    ROOT / "android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png": (192, 192),
    ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@1x.png": (20, 20),
    ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@2x.png": (40, 40),
    ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@3x.png": (60, 60),
    ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@1x.png": (29, 29),
    ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@2x.png": (58, 58),
    ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@3x.png": (87, 87),
    ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@1x.png": (40, 40),
    ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@2x.png": (80, 80),
    ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@3x.png": (120, 120),
    ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@2x.png": (120, 120),
    ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@3x.png": (180, 180),
    ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-76x76@1x.png": (76, 76),
    ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-76x76@2x.png": (152, 152),
    ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-83.5x83.5@2x.png": (167, 167),
    ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png": (1024, 1024),
    ROOT / "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_16.png": (16, 16),
    ROOT / "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_32.png": (32, 32),
    ROOT / "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_64.png": (64, 64),
    ROOT / "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_128.png": (128, 128),
    ROOT / "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_256.png": (256, 256),
    ROOT / "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_512.png": (512, 512),
    ROOT / "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png": (1024, 1024),
    ROOT / "web/favicon.png": (16, 16),
    ROOT / "web/icons/Icon-192.png": (192, 192),
    ROOT / "web/icons/Icon-512.png": (512, 512),
    ROOT / "web/icons/Icon-maskable-192.png": (192, 192),
    ROOT / "web/icons/Icon-maskable-512.png": (512, 512),
}

TV_BANNER_TARGETS: dict[Path, tuple[int, int]] = {
    ROOT / "android/app/src/main/res/drawable-nodpi/tv_banner_hd.png": (1280, 720),
    ROOT / "android/app/src/main/res/drawable-nodpi/tv_banner_preview.png": (1280, 720),
}

LAUNCH_IMAGE_TARGETS: dict[Path, tuple[int, int]] = {
    ROOT / "ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage.png": (180, 180),
    ROOT / "ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage@2x.png": (360, 360),
    ROOT / "ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage@3x.png": (540, 540),
}

WINDOWS_ICON_PATH = ROOT / "windows/runner/resources/app_icon.ico"


def rgba(hex_value: int, alpha: int = 255) -> tuple[int, int, int, int]:
    return (
        (hex_value >> 16) & 0xFF,
        (hex_value >> 8) & 0xFF,
        hex_value & 0xFF,
        alpha,
    )


def lerp_color(
    left: tuple[int, int, int, int],
    right: tuple[int, int, int, int],
    t: float,
) -> tuple[int, int, int, int]:
    clamped = max(0.0, min(1.0, t))
    return tuple(
        int(left[index] * (1.0 - clamped) + right[index] * clamped)
        for index in range(4)
    )


def sample_gradient(
    stops: list[tuple[float, tuple[int, int, int, int]]],
    t: float,
) -> tuple[int, int, int, int]:
    if t <= stops[0][0]:
        return stops[0][1]
    for index in range(len(stops) - 1):
        left_stop, left_color = stops[index]
        right_stop, right_color = stops[index + 1]
        if t <= right_stop:
            local_t = (t - left_stop) / max(right_stop - left_stop, 1e-6)
            return lerp_color(left_color, right_color, local_t)
    return stops[-1][1]


def cubic_bezier_points(
    p0: tuple[float, float],
    p1: tuple[float, float],
    p2: tuple[float, float],
    p3: tuple[float, float],
    *,
    steps: int = 120,
) -> list[tuple[float, float]]:
    points: list[tuple[float, float]] = []
    for index in range(steps + 1):
        t = index / steps
        mt = 1.0 - t
        x = (
            (mt**3) * p0[0]
            + 3 * (mt**2) * t * p1[0]
            + 3 * mt * (t**2) * p2[0]
            + (t**3) * p3[0]
        )
        y = (
            (mt**3) * p0[1]
            + 3 * (mt**2) * t * p1[1]
            + 3 * mt * (t**2) * p2[1]
            + (t**3) * p3[1]
        )
        points.append((x, y))
    return points


def scale_point(
    rect: tuple[float, float, float, float],
    x: float,
    y: float,
) -> tuple[float, float]:
    left, top, right, bottom = rect
    width = right - left
    height = bottom - top
    return (left + width * (x / 96.0), top + height * (y / 96.0))


def apply_masked_image(
    base: Image.Image,
    overlay: Image.Image,
    mask: Image.Image,
) -> None:
    transparent = Image.new("RGBA", base.size, (0, 0, 0, 0))
    transparent.paste(overlay, (0, 0), mask)
    base.alpha_composite(transparent)


def draw_vertical_gradient(
    size: tuple[int, int],
    top_color: tuple[int, int, int, int],
    bottom_color: tuple[int, int, int, int],
) -> Image.Image:
    width, height = size
    gradient = Image.new("RGBA", size)
    gradient_pixels = gradient.load()
    for y in range(height):
        color = lerp_color(top_color, bottom_color, y / max(height - 1, 1))
        for x in range(width):
            gradient_pixels[x, y] = color
    return gradient


def draw_logo_glyph(
    image: Image.Image,
    rect: tuple[float, float, float, float],
) -> None:
    draw = ImageDraw.Draw(image, "RGBA")

    line_specs = [
        (
            cubic_bezier_points(
                scale_point(rect, 18, 62),
                scale_point(rect, 28, 62),
                scale_point(rect, 32, 52),
                scale_point(rect, 42, 52),
            )
            + cubic_bezier_points(
                scale_point(rect, 42, 52),
                scale_point(rect, 52, 52),
                scale_point(rect, 56, 60),
                scale_point(rect, 66, 58),
            )[1:]
            + cubic_bezier_points(
                scale_point(rect, 66, 58),
                scale_point(rect, 72, 57),
                scale_point(rect, 76, 53),
                scale_point(rect, 80, 50),
            )[1:],
            int((rect[2] - rect[0]) * 0.0225),
            [
                (0.0, rgba(0x3D7FFF, 0)),
                (0.4, rgba(0x6EB3FF, 255)),
                (1.0, rgba(0xA5D0FF, 51)),
            ],
        ),
        (
            cubic_bezier_points(
                scale_point(rect, 18, 68),
                scale_point(rect, 30, 68),
                scale_point(rect, 34, 56),
                scale_point(rect, 46, 56),
            )
            + cubic_bezier_points(
                scale_point(rect, 46, 56),
                scale_point(rect, 56, 56),
                scale_point(rect, 60, 64),
                scale_point(rect, 72, 61),
            )[1:]
            + cubic_bezier_points(
                scale_point(rect, 72, 61),
                scale_point(rect, 76, 60),
                scale_point(rect, 79, 57),
                scale_point(rect, 82, 54),
            )[1:],
            int((rect[2] - rect[0]) * 0.0165),
            [
                (0.0, rgba(0x2D5FE0, 0)),
                (0.4, rgba(0x5599EE, 255)),
                (1.0, rgba(0x90C0FF, 51)),
            ],
        ),
        (
            cubic_bezier_points(
                scale_point(rect, 18, 74),
                scale_point(rect, 32, 74),
                scale_point(rect, 36, 62),
                scale_point(rect, 50, 62),
            )
            + cubic_bezier_points(
                scale_point(rect, 50, 62),
                scale_point(rect, 60, 62),
                scale_point(rect, 64, 68),
                scale_point(rect, 76, 65),
            )[1:],
            int((rect[2] - rect[0]) * 0.0125),
            [
                (0.0, rgba(0x1A3DA8, 0)),
                (0.5, rgba(0x4477CC, 255)),
                (1.0, rgba(0x7AACEE, 38)),
            ],
        ),
    ]

    for points, width, stops in line_specs:
        for index in range(len(points) - 1):
            color = sample_gradient(stops, index / max(len(points) - 2, 1))
            draw.line(
                [points[index], points[index + 1]],
                fill=color,
                width=max(width, 1),
                joint="curve",
            )

    star_points = [
        scale_point(rect, 48, 20),
        scale_point(rect, 50.4, 33.6),
        scale_point(rect, 64, 36),
        scale_point(rect, 50.4, 38.4),
        scale_point(rect, 48, 52),
        scale_point(rect, 45.6, 38.4),
        scale_point(rect, 32, 36),
        scale_point(rect, 45.6, 33.6),
    ]
    star_mask = Image.new("L", image.size, 0)
    ImageDraw.Draw(star_mask).polygon(star_points, fill=255)
    star_gradient = draw_vertical_gradient(
        image.size,
        rgba(0xE8F4FF),
        rgba(0x7AB8FF),
    )
    apply_masked_image(image, star_gradient, star_mask)

    sparkle_color = rgba(0xB4D2FF, 150)
    sparkle_width = max(int((rect[2] - rect[0]) * 0.009), 1)
    for start, end in [
        (scale_point(rect, 48, 16), scale_point(rect, 48, 22)),
        (scale_point(rect, 48, 50), scale_point(rect, 48, 56)),
        (scale_point(rect, 28, 36), scale_point(rect, 34, 36)),
        (scale_point(rect, 62, 36), scale_point(rect, 68, 36)),
    ]:
        draw.line([start, end], fill=sparkle_color, width=sparkle_width)


def create_app_icon_master(output_path: Path) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    size = APP_ICON_MASTER_SIZE
    image = Image.new("RGBA", size, (0, 0, 0, 0))

    card_inset = 220
    card_radius = 880
    card_rect = (card_inset, card_inset, size[0] - card_inset, size[1] - card_inset)

    shadow = Image.new("RGBA", size, (0, 0, 0, 0))
    shadow_mask = Image.new("L", size, 0)
    ImageDraw.Draw(shadow_mask).rounded_rectangle(card_rect, radius=card_radius, fill=255)
    shadow_layer = Image.new("RGBA", size, rgba(0x000000, 118))
    shadow.paste(shadow_layer, (0, 0), shadow_mask)
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=84))
    image.alpha_composite(shadow)

    card_mask = Image.new("L", size, 0)
    ImageDraw.Draw(card_mask).rounded_rectangle(card_rect, radius=card_radius, fill=255)

    card_gradient = draw_vertical_gradient(size, rgba(0x1A2A4A), rgba(0x0D1525))
    apply_masked_image(image, card_gradient, card_mask)

    bottom_shade = Image.new("RGBA", size, (0, 0, 0, 0))
    bottom_gradient = draw_vertical_gradient(size, rgba(0x000000, 0), rgba(0x000000, 54))
    apply_masked_image(bottom_shade, bottom_gradient, card_mask)
    image.alpha_composite(bottom_shade)

    glyph_rect = (
        card_inset + 360,
        card_inset + 360,
        size[0] - card_inset - 360,
        size[1] - card_inset - 360,
    )
    draw_logo_glyph(image, glyph_rect)

    image.save(output_path)
    print(f"Generated {output_path.relative_to(ROOT)}")


def find_edge() -> Path:
    env_override = os.environ.get("EDGE_PATH")
    if env_override:
        edge = Path(env_override)
        if edge.exists():
            return edge

    candidates = [
        Path(r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"),
        Path(r"C:\Program Files\Microsoft\Edge\Application\msedge.exe"),
    ]
    for candidate in candidates:
        if candidate.exists():
            return candidate

    for executable in ("msedge", "microsoft-edge", "edge"):
        resolved = shutil.which(executable)
        if resolved:
            return Path(resolved)

    raise FileNotFoundError(
        "Could not find Microsoft Edge. Set EDGE_PATH to the browser executable."
    )


def render_file(
    *,
    edge_path: Path,
    source_path: Path,
    output_path: Path,
    viewport: tuple[int, int],
    scale: int,
    wait_ms: int = 8000,
) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    command = [
        str(edge_path),
        "--headless=new",
        "--disable-gpu",
        "--hide-scrollbars",
        "--run-all-compositor-stages-before-draw",
        "--allow-file-access-from-files",
        "--default-background-color=00000000",
        f"--window-size={viewport[0]},{viewport[1]}",
        f"--force-device-scale-factor={scale}",
        f"--virtual-time-budget={wait_ms}",
        f"--screenshot={output_path}",
        source_path.resolve().as_uri(),
    ]
    completed = subprocess.run(
        command,
        cwd=ROOT,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    if completed.stdout.strip():
        print(completed.stdout.strip())


def resize_image(source: Path, destination: Path, size: tuple[int, int]) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    with Image.open(source) as image:
        rendered = image.convert("RGBA").resize(size, Image.Resampling.LANCZOS)
        if max(size) <= 256:
            rendered = rendered.filter(
                ImageFilter.UnsharpMask(radius=1.15, percent=165, threshold=1)
            )
        rendered.save(destination)
    print(f"Generated {destination.relative_to(ROOT)}")


def copy_png(source: Path, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    with Image.open(source) as image:
        image.convert("RGBA").save(destination)
    print(f"Generated {destination.relative_to(ROOT)}")


def crop_image(source: Path, destination: Path, size: tuple[int, int]) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    with Image.open(source) as image:
        cropped = image.convert("RGBA").crop((0, 0, size[0], size[1]))
        cropped.save(destination)
    print(f"Cropped {destination.relative_to(ROOT)}")


def save_windows_icon(source: Path, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    with Image.open(source) as image:
        image.convert("RGBA").save(
            destination,
            format="ICO",
            sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
        )
    print(f"Generated {destination.relative_to(ROOT)}")


def main() -> int:
    edge_path = find_edge()
    BUILD_DIR.mkdir(parents=True, exist_ok=True)

    app_icon_capture = BUILD_DIR / "app_icon_raw_capture.png"
    app_icon_master = BUILD_DIR / "starflow_app_icon_master.png"
    tv_banner_master = BUILD_DIR / "starflow_tv_banner_master.png"

    render_file(
        edge_path=edge_path,
        source_path=APP_ICON_SVG,
        output_path=app_icon_capture,
        viewport=APP_ICON_VIEWPORT,
        scale=APP_ICON_SCALE,
        wait_ms=2000,
    )
    copy_png(app_icon_capture, app_icon_master)

    render_file(
        edge_path=edge_path,
        source_path=TV_BANNER_HTML,
        output_path=tv_banner_master,
        viewport=TV_BANNER_CAPTURE_VIEWPORT,
        scale=TV_BANNER_SCALE,
    )
    crop_image(
        tv_banner_master,
        tv_banner_master,
        (TV_BANNER_VIEWPORT[0] * TV_BANNER_SCALE, TV_BANNER_VIEWPORT[1] * TV_BANNER_SCALE),
    )

    for path, size in APP_ICON_TARGETS.items():
        resize_image(app_icon_master, path, size)

    for path, size in TV_BANNER_TARGETS.items():
        resize_image(tv_banner_master, path, size)

    for path, size in LAUNCH_IMAGE_TARGETS.items():
        resize_image(app_icon_master, path, size)

    save_windows_icon(app_icon_master, WINDOWS_ICON_PATH)
    return 0


if __name__ == "__main__":
    sys.exit(main())
