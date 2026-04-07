from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
from pathlib import Path
from xml.etree import ElementTree as ET

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

LAUNCH_LOGO_TARGETS: dict[Path, tuple[int, int]] = {
    ROOT / "assets/branding/starflow_launch_logo.png": (512, 512),
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


SVG_NAMESPACE = "{http://www.w3.org/2000/svg}"
SVG_PATH_TOKEN = re.compile(r"[A-Za-z]|[-+]?(?:\d+\.\d+|\d+|\.\d+)(?:[eE][-+]?\d+)?")


def strip_svg_namespace(tag: str) -> str:
    return tag.split("}", 1)[-1]


def parse_viewbox(value: str) -> tuple[float, float, float, float]:
    parts = [float(part) for part in value.replace(",", " ").split()]
    if len(parts) != 4:
        raise ValueError(f"Unexpected viewBox: {value}")
    return (parts[0], parts[1], parts[2], parts[3])


def parse_svg_number(value: str | None, default: float = 0.0) -> float:
    if value is None:
        return default
    return float(value)


def parse_svg_opacity(value: str | None, default: float = 1.0) -> float:
    if value is None:
        return default
    return float(value)


def apply_opacity(
    color: tuple[int, int, int, int],
    opacity: float,
) -> tuple[int, int, int, int]:
    clamped = max(0.0, min(1.0, opacity))
    return (color[0], color[1], color[2], int(color[3] * clamped))


def parse_svg_color(
    value: str,
    *,
    opacity: float = 1.0,
) -> tuple[int, int, int, int]:
    text = value.strip()
    if text.startswith("#"):
        hex_value = text[1:]
        if len(hex_value) == 6:
            alpha = 255
        elif len(hex_value) == 8:
            alpha = int(hex_value[6:8], 16)
            hex_value = hex_value[:6]
        else:
            raise ValueError(f"Unsupported hex color: {value}")
        color = (
            int(hex_value[0:2], 16),
            int(hex_value[2:4], 16),
            int(hex_value[4:6], 16),
            alpha,
        )
        return apply_opacity(color, opacity)
    if text.startswith("rgba(") and text.endswith(")"):
        parts = [part.strip() for part in text[5:-1].split(",")]
        if len(parts) != 4:
            raise ValueError(f"Unsupported rgba color: {value}")
        color = (
            int(float(parts[0])),
            int(float(parts[1])),
            int(float(parts[2])),
            int(float(parts[3]) * 255),
        )
        return apply_opacity(color, opacity)
    if text.startswith("rgb(") and text.endswith(")"):
        parts = [part.strip() for part in text[4:-1].split(",")]
        if len(parts) != 3:
            raise ValueError(f"Unsupported rgb color: {value}")
        color = (
            int(float(parts[0])),
            int(float(parts[1])),
            int(float(parts[2])),
            255,
        )
        return apply_opacity(color, opacity)
    raise ValueError(f"Unsupported SVG color: {value}")


def parse_svg_offset(value: str | None) -> float:
    if not value:
        return 0.0
    text = value.strip()
    if text.endswith("%"):
        return float(text[:-1]) / 100.0
    return float(text)


def build_transform(
    offset: tuple[float, float],
    size: tuple[float, float],
    viewbox: tuple[float, float, float, float],
):
    offset_x, offset_y = offset
    width, height = size
    viewbox_x, viewbox_y, viewbox_width, viewbox_height = viewbox
    scale_x = width / viewbox_width
    scale_y = height / viewbox_height

    def transform_point(point: tuple[float, float]) -> tuple[float, float]:
        return (
            offset_x + (point[0] - viewbox_x) * scale_x,
            offset_y + (point[1] - viewbox_y) * scale_y,
        )

    def transform_length(value: float) -> float:
        return value * ((scale_x + scale_y) / 2.0)

    return transform_point, transform_length, scale_x, scale_y


def parse_gradient_definitions(
    defs_element: ET.Element | None,
    transform_point,
) -> dict[str, dict[str, object]]:
    gradients: dict[str, dict[str, object]] = {}
    if defs_element is None:
        return gradients

    for gradient in defs_element:
        if strip_svg_namespace(gradient.tag) != "linearGradient":
            continue
        gradient_id = gradient.get("id")
        if not gradient_id:
            continue
        start = transform_point(
            (
                parse_svg_number(gradient.get("x1")),
                parse_svg_number(gradient.get("y1")),
            )
        )
        end = transform_point(
            (
                parse_svg_number(gradient.get("x2")),
                parse_svg_number(gradient.get("y2")),
            )
        )
        stops: list[tuple[float, tuple[int, int, int, int]]] = []
        for stop in gradient:
            if strip_svg_namespace(stop.tag) != "stop":
                continue
            stop_opacity = parse_svg_opacity(stop.get("stop-opacity"))
            stops.append(
                (
                    parse_svg_offset(stop.get("offset")),
                    parse_svg_color(stop.get("stop-color", "#000000"), opacity=stop_opacity),
                )
            )
        gradients[gradient_id] = {"start": start, "end": end, "stops": stops}
    return gradients


def draw_linear_gradient(
    size: tuple[int, int],
    start: tuple[float, float],
    end: tuple[float, float],
    stops: list[tuple[float, tuple[int, int, int, int]]],
) -> Image.Image:
    width, height = size
    gradient = Image.new("RGBA", size)
    gradient_pixels = gradient.load()
    delta_x = end[0] - start[0]
    delta_y = end[1] - start[1]
    denominator = max(delta_x * delta_x + delta_y * delta_y, 1e-6)

    for y in range(height):
        for x in range(width):
            t = ((x - start[0]) * delta_x + (y - start[1]) * delta_y) / denominator
            gradient_pixels[x, y] = sample_gradient(stops, t)
    return gradient


def parse_url_reference(value: str | None) -> str | None:
    if not value:
        return None
    text = value.strip()
    if text.startswith("url(#") and text.endswith(")"):
        return text[5:-1]
    return None


def parse_svg_path_commands(path_data: str) -> list[tuple]:
    tokens = SVG_PATH_TOKEN.findall(path_data)
    commands: list[tuple] = []
    index = 0
    current = (0.0, 0.0)
    subpath_start = current
    active_command: str | None = None

    while index < len(tokens):
        token = tokens[index]
        if token.isalpha():
            active_command = token
            index += 1
            if active_command in {"Z", "z"}:
                commands.append(("Z", current, subpath_start))
                current = subpath_start
                active_command = None
            continue

        if active_command is None:
            raise ValueError(f"Unexpected SVG path data: {path_data}")

        if active_command in {"M", "m"}:
            x = float(tokens[index])
            y = float(tokens[index + 1])
            index += 2
            if active_command == "m":
                current = (current[0] + x, current[1] + y)
            else:
                current = (x, y)
            subpath_start = current
            commands.append(("M", current))
            active_command = "L" if active_command == "M" else "l"
            continue

        if active_command in {"L", "l"}:
            x = float(tokens[index])
            y = float(tokens[index + 1])
            index += 2
            if active_command == "l":
                next_point = (current[0] + x, current[1] + y)
            else:
                next_point = (x, y)
            commands.append(("L", current, next_point))
            current = next_point
            continue

        if active_command in {"C", "c"}:
            values = [float(token_value) for token_value in tokens[index:index + 6]]
            index += 6
            if active_command == "c":
                control_1 = (current[0] + values[0], current[1] + values[1])
                control_2 = (current[0] + values[2], current[1] + values[3])
                next_point = (current[0] + values[4], current[1] + values[5])
            else:
                control_1 = (values[0], values[1])
                control_2 = (values[2], values[3])
                next_point = (values[4], values[5])
            commands.append(("C", current, control_1, control_2, next_point))
            current = next_point
            continue

        raise ValueError(f"Unsupported SVG path command: {active_command}")

    return commands


def transform_path_commands(commands: list[tuple], transform_point) -> list[tuple]:
    transformed: list[tuple] = []
    for command in commands:
        opcode = command[0]
        if opcode == "M":
            transformed.append(("M", transform_point(command[1])))
        elif opcode == "L":
            transformed.append(("L", transform_point(command[1]), transform_point(command[2])))
        elif opcode == "C":
            transformed.append(
                (
                    "C",
                    transform_point(command[1]),
                    transform_point(command[2]),
                    transform_point(command[3]),
                    transform_point(command[4]),
                )
            )
        elif opcode == "Z":
            transformed.append(("Z", transform_point(command[1]), transform_point(command[2])))
    return transformed


def path_commands_to_points(
    commands: list[tuple],
    *,
    curve_steps: int = 120,
) -> list[tuple[float, float]]:
    points: list[tuple[float, float]] = []
    for command in commands:
        opcode = command[0]
        if opcode == "M":
            points.append(command[1])
        elif opcode == "L":
            if not points:
                points.append(command[1])
            points.append(command[2])
        elif opcode == "C":
            if not points:
                points.append(command[1])
            bezier_points = cubic_bezier_points(
                command[1],
                command[2],
                command[3],
                command[4],
                steps=curve_steps,
            )
            points.extend(bezier_points[1:])
        elif opcode == "Z":
            if points and points[-1] != command[2]:
                points.append(command[2])
    return points


def sample_linear_gradient_color(
    gradient: dict[str, object],
    point: tuple[float, float],
) -> tuple[int, int, int, int]:
    start = gradient["start"]
    end = gradient["end"]
    stops = gradient["stops"]
    delta_x = end[0] - start[0]
    delta_y = end[1] - start[1]
    denominator = max(delta_x * delta_x + delta_y * delta_y, 1e-6)
    t = ((point[0] - start[0]) * delta_x + (point[1] - start[1]) * delta_y) / denominator
    return sample_gradient(stops, t)


def render_app_icon_from_svg(
    svg_path: Path,
    output_path: Path,
    size: tuple[int, int],
) -> None:
    tree = ET.parse(svg_path)
    root = tree.getroot()
    viewbox = parse_viewbox(root.get("viewBox", "0 0 1024 1024"))
    transform_root_point, _, _, _ = build_transform((0.0, 0.0), size, viewbox)
    image = Image.new("RGBA", size, (0, 0, 0, 0))

    root_gradients = parse_gradient_definitions(root.find(f"{SVG_NAMESPACE}defs"), transform_root_point)
    root_rect = next(
        child for child in root
        if strip_svg_namespace(child.tag) == "rect"
    )
    rect_x = parse_svg_number(root_rect.get("x"))
    rect_y = parse_svg_number(root_rect.get("y"))
    rect_width = parse_svg_number(root_rect.get("width"), viewbox[2])
    rect_height = parse_svg_number(root_rect.get("height"), viewbox[3])
    rect_rx = parse_svg_number(root_rect.get("rx"))
    top_left = transform_root_point((rect_x, rect_y))
    bottom_right = transform_root_point((rect_x + rect_width, rect_y + rect_height))
    radius = int((bottom_right[0] - top_left[0]) * (rect_rx / max(rect_width, 1.0)))
    rect_mask = Image.new("L", size, 0)
    ImageDraw.Draw(rect_mask).rounded_rectangle(
        (top_left[0], top_left[1], bottom_right[0], bottom_right[1]),
        radius=radius,
        fill=255,
    )
    rect_gradient_id = parse_url_reference(root_rect.get("fill"))
    if rect_gradient_id is None:
        raise ValueError("App icon rect is missing gradient fill")
    rect_gradient = root_gradients[rect_gradient_id]
    background = draw_linear_gradient(size, rect_gradient["start"], rect_gradient["end"], rect_gradient["stops"])
    apply_masked_image(image, background, rect_mask)

    nested_svg = next(
        child for child in root
        if strip_svg_namespace(child.tag) == "svg"
    )
    nested_viewbox = parse_viewbox(nested_svg.get("viewBox", "0 0 96 96"))
    nested_origin = transform_root_point(
        (
            parse_svg_number(nested_svg.get("x")),
            parse_svg_number(nested_svg.get("y")),
        )
    )
    nested_size = (
        parse_svg_number(nested_svg.get("width")) * (size[0] / viewbox[2]),
        parse_svg_number(nested_svg.get("height")) * (size[1] / viewbox[3]),
    )
    transform_nested_point, transform_nested_length, _, _ = build_transform(
        nested_origin,
        nested_size,
        nested_viewbox,
    )
    nested_gradients = parse_gradient_definitions(
        nested_svg.find(f"{SVG_NAMESPACE}defs"),
        transform_nested_point,
    )

    draw = ImageDraw.Draw(image, "RGBA")
    for child in nested_svg:
        tag = strip_svg_namespace(child.tag)
        if tag == "defs":
            continue

        opacity = parse_svg_opacity(child.get("opacity"))
        if tag == "line":
            color = parse_svg_color(child.get("stroke", "#000000"), opacity=opacity)
            start = transform_nested_point(
                (
                    parse_svg_number(child.get("x1")),
                    parse_svg_number(child.get("y1")),
                )
            )
            end = transform_nested_point(
                (
                    parse_svg_number(child.get("x2")),
                    parse_svg_number(child.get("y2")),
                )
            )
            width = max(int(round(transform_nested_length(parse_svg_number(child.get("stroke-width"), 1.0)))), 1)
            draw.line([start, end], fill=color, width=width)
            continue

        if tag != "path":
            continue

        commands = transform_path_commands(
            parse_svg_path_commands(child.get("d", "")),
            transform_nested_point,
        )

        fill_gradient_id = parse_url_reference(child.get("fill"))
        if fill_gradient_id:
            points = path_commands_to_points(commands, curve_steps=40)
            mask = Image.new("L", size, 0)
            ImageDraw.Draw(mask).polygon(points, fill=255)
            gradient = nested_gradients[fill_gradient_id]
            fill_image = draw_linear_gradient(size, gradient["start"], gradient["end"], gradient["stops"])
            apply_masked_image(image, fill_image, mask)

        stroke_gradient_id = parse_url_reference(child.get("stroke"))
        if stroke_gradient_id:
            points = path_commands_to_points(commands, curve_steps=36)
            gradient = nested_gradients[stroke_gradient_id]
            width = max(int(round(transform_nested_length(parse_svg_number(child.get("stroke-width"), 1.0)))), 1)
            stroke_mask = Image.new("L", size, 0)
            ImageDraw.Draw(stroke_mask).line(points, fill=255, width=width, joint="curve")
            if opacity < 1.0:
                stroke_mask = stroke_mask.point(lambda value: int(value * opacity))
            stroke_image = draw_linear_gradient(size, gradient["start"], gradient["end"], gradient["stops"])
            apply_masked_image(image, stroke_image, stroke_mask)

    output_path.parent.mkdir(parents=True, exist_ok=True)
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

    render_app_icon_from_svg(
        APP_ICON_SVG,
        app_icon_capture,
        APP_ICON_MASTER_SIZE,
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
