from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
BUILD_DIR = ROOT / "build" / "brand_assets"
APP_ICON_HTML = ROOT / "docs" / "starflow_app_icon.html"
TV_BANNER_HTML = ROOT / "docs" / "starflow_tv_banner.html"

APP_ICON_VIEWPORT = (1024, 1024)
APP_ICON_SCALE = 4
APP_ICON_CAPTURE_VIEWPORT = (1054, 1119)
TV_BANNER_VIEWPORT = (1280, 720)
TV_BANNER_SCALE = 3
TV_BANNER_CAPTURE_VIEWPORT = (1280, 815)

APP_ICON_TARGETS: dict[Path, tuple[int, int]] = {
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

WINDOWS_ICON_PATH = ROOT / "windows/runner/resources/app_icon.ico"


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


def render_html(
    *,
    edge_path: Path,
    html_path: Path,
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
        html_path.resolve().as_uri(),
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
        rendered.save(destination)
    print(f"Generated {destination.relative_to(ROOT)}")


def crop_image(source: Path, destination: Path, size: tuple[int, int]) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    with Image.open(source) as image:
        cropped = image.convert("RGBA").crop((0, 0, size[0], size[1]))
        cropped.save(destination)
    print(f"Cropped {destination.relative_to(ROOT)}")


def crop_image_centered(source: Path, destination: Path, size: tuple[int, int]) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    with Image.open(source) as image:
        rendered = image.convert("RGBA")
        left = max((rendered.width - size[0]) // 2, 0)
        top = max((rendered.height - size[1]) // 2, 0)
        cropped = rendered.crop((left, top, left + size[0], top + size[1]))
        cropped.save(destination)
    print(f"Center-cropped {destination.relative_to(ROOT)}")


def save_windows_icon(source: Path, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    with Image.open(source) as image:
        image = image.convert("RGBA")
        image.save(
            destination,
            format="ICO",
            sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
        )
    print(f"Generated {destination.relative_to(ROOT)}")


def main() -> int:
    edge_path = find_edge()
    BUILD_DIR.mkdir(parents=True, exist_ok=True)

    app_icon_raw_capture = BUILD_DIR / "app_icon_raw_capture.png"
    app_icon_master = BUILD_DIR / "starflow_app_icon_master.png"
    tv_banner_master = BUILD_DIR / "starflow_tv_banner_master.png"

    render_html(
        edge_path=edge_path,
        html_path=APP_ICON_HTML,
        output_path=app_icon_raw_capture,
        viewport=APP_ICON_CAPTURE_VIEWPORT,
        scale=APP_ICON_SCALE,
    )
    crop_image_centered(
        app_icon_raw_capture,
        app_icon_master,
        (APP_ICON_VIEWPORT[0] * APP_ICON_SCALE, APP_ICON_VIEWPORT[1] * APP_ICON_SCALE),
    )
    render_html(
        edge_path=edge_path,
        html_path=TV_BANNER_HTML,
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

    save_windows_icon(app_icon_master, WINDOWS_ICON_PATH)
    return 0


if __name__ == "__main__":
    sys.exit(main())
