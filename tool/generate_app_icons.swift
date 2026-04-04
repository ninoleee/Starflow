import AppKit
import Foundation

struct IconTarget {
  let path: String
  let size: CGFloat
}

let targets: [IconTarget] = [
  IconTarget(path: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@1x.png", size: 20),
  IconTarget(path: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@2x.png", size: 40),
  IconTarget(path: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@3x.png", size: 60),
  IconTarget(path: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@1x.png", size: 29),
  IconTarget(path: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@2x.png", size: 58),
  IconTarget(path: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@3x.png", size: 87),
  IconTarget(path: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@1x.png", size: 40),
  IconTarget(path: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@2x.png", size: 80),
  IconTarget(path: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@3x.png", size: 120),
  IconTarget(path: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@2x.png", size: 120),
  IconTarget(path: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@3x.png", size: 180),
  IconTarget(path: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-76x76@1x.png", size: 76),
  IconTarget(path: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-76x76@2x.png", size: 152),
  IconTarget(path: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-83.5x83.5@2x.png", size: 167),
  IconTarget(path: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png", size: 1024),
  IconTarget(path: "android/app/src/main/res/mipmap-mdpi/ic_launcher.png", size: 48),
  IconTarget(path: "android/app/src/main/res/mipmap-hdpi/ic_launcher.png", size: 72),
  IconTarget(path: "android/app/src/main/res/mipmap-xhdpi/ic_launcher.png", size: 96),
  IconTarget(path: "android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png", size: 144),
  IconTarget(path: "android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png", size: 192),
  IconTarget(path: "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_16.png", size: 16),
  IconTarget(path: "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_32.png", size: 32),
  IconTarget(path: "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_64.png", size: 64),
  IconTarget(path: "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_128.png", size: 128),
  IconTarget(path: "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_256.png", size: 256),
  IconTarget(path: "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_512.png", size: 512),
  IconTarget(path: "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png", size: 1024),
]

func color(_ hex: UInt32, alpha: CGFloat = 1.0) -> NSColor {
  let red = CGFloat((hex >> 16) & 0xFF) / 255.0
  let green = CGFloat((hex >> 8) & 0xFF) / 255.0
  let blue = CGFloat(hex & 0xFF) / 255.0
  return NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
}

func point(_ x: CGFloat, _ y: CGFloat, in rect: CGRect) -> CGPoint {
  CGPoint(
    x: rect.origin.x + rect.width * x / 96.0,
    y: rect.origin.y + rect.height * y / 96.0
  )
}

func gradientImage(size: CGSize, draw: (CGContext, CGRect) -> Void) -> NSImage {
  let image = NSImage(size: size)
  image.lockFocus()
  guard let context = NSGraphicsContext.current?.cgContext else {
    image.unlockFocus()
    return image
  }

  let rect = CGRect(origin: .zero, size: size)
  draw(context, rect)
  context.flush()
  image.unlockFocus()
  return image
}

func drawLinearStroke(
  _ context: CGContext,
  path: CGPath,
  width: CGFloat,
  colors: [NSColor],
  locations: [CGFloat],
  start: CGPoint,
  end: CGPoint
) {
  context.saveGState()
  context.addPath(path)
  context.setLineWidth(width)
  context.setLineCap(.round)
  context.replacePathWithStrokedPath()
  context.clip()
  let cgColors = colors.map { $0.cgColor } as CFArray
  let gradient = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: cgColors,
    locations: locations
  )!
  context.drawLinearGradient(gradient, start: start, end: end, options: [])
  context.restoreGState()
}

func drawAppIcon(size: CGFloat) -> NSImage {
  gradientImage(size: CGSize(width: size, height: size)) { context, rect in
    context.interpolationQuality = .high

    let backgroundGradient = CGGradient(
      colorsSpace: CGColorSpaceCreateDeviceRGB(),
      colors: [
        color(0x1A2A4A).cgColor,
        color(0x0D1525).cgColor,
      ] as CFArray,
      locations: [0.0, 1.0]
    )!
    context.drawLinearGradient(
      backgroundGradient,
      start: CGPoint(x: rect.minX, y: rect.maxY),
      end: CGPoint(x: rect.maxX, y: rect.minY),
      options: []
    )

    let innerGlowCenter = CGPoint(x: rect.midX, y: rect.midY + rect.height * 0.08)
    let innerGlow = CGGradient(
      colorsSpace: CGColorSpaceCreateDeviceRGB(),
      colors: [
        color(0x64A0FF, alpha: 0.20).cgColor,
        color(0x64A0FF, alpha: 0.0).cgColor,
      ] as CFArray,
      locations: [0.0, 1.0]
    )!
    context.drawRadialGradient(
      innerGlow,
      startCenter: innerGlowCenter,
      startRadius: 0,
      endCenter: innerGlowCenter,
      endRadius: rect.width * 0.7,
      options: []
    )

    let cardInset = rect.width * 0.12
    let cardRect = rect.insetBy(dx: cardInset, dy: cardInset)
    let radius = rect.width * 0.22
    let cardPath = CGPath(
      roundedRect: cardRect,
      cornerWidth: radius,
      cornerHeight: radius,
      transform: nil
    )
    context.saveGState()
    context.addPath(cardPath)
    context.clip()
    let cardGradient = CGGradient(
      colorsSpace: CGColorSpaceCreateDeviceRGB(),
      colors: [
        color(0x0D1117).cgColor,
        color(0x161B27).cgColor,
      ] as CFArray,
      locations: [0.0, 1.0]
    )!
    context.drawLinearGradient(
      cardGradient,
      start: CGPoint(x: cardRect.minX, y: cardRect.maxY),
      end: CGPoint(x: cardRect.maxX, y: cardRect.minY),
      options: []
    )
    context.restoreGState()

    context.setStrokeColor(color(0xFFFFFF, alpha: 0.08).cgColor)
    context.setLineWidth(max(1, rect.width * 0.006))
    context.addPath(cardPath)
    context.strokePath()

    let iconRect = cardRect.insetBy(dx: cardRect.width * 0.12, dy: cardRect.height * 0.12)

    let line1 = CGMutablePath()
    line1.move(to: point(18, 62, in: iconRect))
    line1.addCurve(to: point(42, 52, in: iconRect), control1: point(28, 62, in: iconRect), control2: point(32, 52, in: iconRect))
    line1.addCurve(to: point(66, 58, in: iconRect), control1: point(52, 52, in: iconRect), control2: point(56, 60, in: iconRect))
    line1.addCurve(to: point(80, 50, in: iconRect), control1: point(72, 57, in: iconRect), control2: point(76, 53, in: iconRect))
    drawLinearStroke(
      context,
      path: line1,
      width: rect.width * 0.017,
      colors: [color(0x3D7FFF, alpha: 0.0), color(0x6EB3FF), color(0xA5D0FF, alpha: 0.22)],
      locations: [0.0, 0.4, 1.0],
      start: point(18, 56, in: iconRect),
      end: point(80, 56, in: iconRect)
    )

    let line2 = CGMutablePath()
    line2.move(to: point(18, 68, in: iconRect))
    line2.addCurve(to: point(46, 56, in: iconRect), control1: point(30, 68, in: iconRect), control2: point(34, 56, in: iconRect))
    line2.addCurve(to: point(72, 61, in: iconRect), control1: point(56, 56, in: iconRect), control2: point(60, 64, in: iconRect))
    line2.addCurve(to: point(82, 54, in: iconRect), control1: point(76, 60, in: iconRect), control2: point(79, 57, in: iconRect))
    drawLinearStroke(
      context,
      path: line2,
      width: rect.width * 0.013,
      colors: [color(0x2D5FE0, alpha: 0.0), color(0x5599EE), color(0x90C0FF, alpha: 0.22)],
      locations: [0.0, 0.4, 1.0],
      start: point(18, 62, in: iconRect),
      end: point(82, 62, in: iconRect)
    )

    let line3 = CGMutablePath()
    line3.move(to: point(18, 74, in: iconRect))
    line3.addCurve(to: point(50, 62, in: iconRect), control1: point(32, 74, in: iconRect), control2: point(36, 62, in: iconRect))
    line3.addCurve(to: point(76, 65, in: iconRect), control1: point(60, 62, in: iconRect), control2: point(64, 68, in: iconRect))
    drawLinearStroke(
      context,
      path: line3,
      width: rect.width * 0.010,
      colors: [color(0x1A3DA8, alpha: 0.0), color(0x4477CC), color(0x7AACEE, alpha: 0.16)],
      locations: [0.0, 0.5, 1.0],
      start: point(18, 68, in: iconRect),
      end: point(76, 68, in: iconRect)
    )

    let starPath = CGMutablePath()
    starPath.move(to: point(48, 20, in: iconRect))
    starPath.addLine(to: point(50.4, 33.6, in: iconRect))
    starPath.addLine(to: point(64, 36, in: iconRect))
    starPath.addLine(to: point(50.4, 38.4, in: iconRect))
    starPath.addLine(to: point(48, 52, in: iconRect))
    starPath.addLine(to: point(45.6, 38.4, in: iconRect))
    starPath.addLine(to: point(32, 36, in: iconRect))
    starPath.addLine(to: point(45.6, 33.6, in: iconRect))
    starPath.closeSubpath()

    context.saveGState()
    context.addPath(starPath)
    context.clip()
    let starGradient = CGGradient(
      colorsSpace: CGColorSpaceCreateDeviceRGB(),
      colors: [
        color(0xE8F4FF).cgColor,
        color(0x7AB8FF).cgColor,
      ] as CFArray,
      locations: [0.0, 1.0]
    )!
    context.drawLinearGradient(
      starGradient,
      start: point(32, 20, in: iconRect),
      end: point(64, 52, in: iconRect),
      options: []
    )
    context.restoreGState()

    context.setStrokeColor(color(0xB4D2FF, alpha: 0.55).cgColor)
    context.setLineWidth(max(1, rect.width * 0.008))
    context.setLineCap(.round)
    let sparkleLines = [
      (point(48, 16, in: iconRect), point(48, 22, in: iconRect)),
      (point(48, 50, in: iconRect), point(48, 56, in: iconRect)),
      (point(28, 36, in: iconRect), point(34, 36, in: iconRect)),
      (point(62, 36, in: iconRect), point(68, 36, in: iconRect)),
    ]
    for (start, end) in sparkleLines {
      context.move(to: start)
      context.addLine(to: end)
      context.strokePath()
    }
  }
}

func savePNG(_ image: NSImage, to path: String) throws {
  guard let tiff = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff),
        let data = bitmap.representation(using: .png, properties: [:]) else {
    throw NSError(domain: "StarflowIcon", code: 1, userInfo: [
      NSLocalizedDescriptionKey: "Failed to encode PNG for \(path)",
    ])
  }

  let url = URL(fileURLWithPath: path)
  try FileManager.default.createDirectory(
    at: url.deletingLastPathComponent(),
    withIntermediateDirectories: true
  )
  try data.write(to: url)
}

for target in targets {
  let image = drawAppIcon(size: target.size)
  try savePNG(image, to: target.path)
  print("Generated \(target.path)")
}
