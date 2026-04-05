import AppKit
import Foundation

struct IconTarget {
  let path: String
  let size: CGFloat
}

struct LaunchTarget {
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

let launchTargets: [LaunchTarget] = [
  LaunchTarget(path: "ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage.png", size: 180),
  LaunchTarget(path: "ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage@2x.png", size: 360),
  LaunchTarget(path: "ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage@3x.png", size: 540),
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

func makeBitmap(size: CGFloat, draw: (CGContext, CGRect) -> Void) throws -> NSBitmapImageRep {
  let pixelSize = Int(size.rounded())
  guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: pixelSize,
    pixelsHigh: pixelSize,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
  ) else {
    throw NSError(domain: "StarflowIcon", code: 2, userInfo: [
      NSLocalizedDescriptionKey: "Failed to create bitmap for \(pixelSize)x\(pixelSize)",
    ])
  }

  bitmap.size = NSSize(width: size, height: size)
  guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    throw NSError(domain: "StarflowIcon", code: 3, userInfo: [
      NSLocalizedDescriptionKey: "Failed to create graphics context",
    ])
  }

  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = context
  context.cgContext.interpolationQuality = .high
  let rect = CGRect(x: 0, y: 0, width: size, height: size)
  draw(context.cgContext, rect)
  context.flushGraphics()
  NSGraphicsContext.restoreGraphicsState()

  return bitmap
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

func drawLogoGlyph(_ context: CGContext, in rect: CGRect) {
  let line1 = CGMutablePath()
  line1.move(to: point(18, 62, in: rect))
  line1.addCurve(to: point(42, 52, in: rect), control1: point(28, 62, in: rect), control2: point(32, 52, in: rect))
  line1.addCurve(to: point(66, 58, in: rect), control1: point(52, 52, in: rect), control2: point(56, 60, in: rect))
  line1.addCurve(to: point(80, 50, in: rect), control1: point(72, 57, in: rect), control2: point(76, 53, in: rect))
  drawLinearStroke(
    context,
    path: line1,
    width: rect.width * 0.018,
    colors: [color(0x3D7FFF, alpha: 0.0), color(0x6EB3FF), color(0xA5D0FF, alpha: 0.22)],
    locations: [0.0, 0.4, 1.0],
    start: point(18, 56, in: rect),
    end: point(80, 56, in: rect)
  )

  let line2 = CGMutablePath()
  line2.move(to: point(18, 68, in: rect))
  line2.addCurve(to: point(46, 56, in: rect), control1: point(30, 68, in: rect), control2: point(34, 56, in: rect))
  line2.addCurve(to: point(72, 61, in: rect), control1: point(56, 56, in: rect), control2: point(60, 64, in: rect))
  line2.addCurve(to: point(82, 54, in: rect), control1: point(76, 60, in: rect), control2: point(79, 57, in: rect))
  drawLinearStroke(
    context,
    path: line2,
    width: rect.width * 0.014,
    colors: [color(0x2D5FE0, alpha: 0.0), color(0x5599EE), color(0x90C0FF, alpha: 0.22)],
    locations: [0.0, 0.4, 1.0],
    start: point(18, 62, in: rect),
    end: point(82, 62, in: rect)
  )

  let line3 = CGMutablePath()
  line3.move(to: point(18, 74, in: rect))
  line3.addCurve(to: point(50, 62, in: rect), control1: point(32, 74, in: rect), control2: point(36, 62, in: rect))
  line3.addCurve(to: point(76, 65, in: rect), control1: point(60, 62, in: rect), control2: point(64, 68, in: rect))
  drawLinearStroke(
    context,
    path: line3,
    width: rect.width * 0.011,
    colors: [color(0x1A3DA8, alpha: 0.0), color(0x4477CC), color(0x7AACEE, alpha: 0.16)],
    locations: [0.0, 0.5, 1.0],
    start: point(18, 68, in: rect),
    end: point(76, 68, in: rect)
  )

  let starPath = CGMutablePath()
  starPath.move(to: point(48, 20, in: rect))
  starPath.addLine(to: point(50.4, 33.6, in: rect))
  starPath.addLine(to: point(64, 36, in: rect))
  starPath.addLine(to: point(50.4, 38.4, in: rect))
  starPath.addLine(to: point(48, 52, in: rect))
  starPath.addLine(to: point(45.6, 38.4, in: rect))
  starPath.addLine(to: point(32, 36, in: rect))
  starPath.addLine(to: point(45.6, 33.6, in: rect))
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
    start: point(32, 20, in: rect),
    end: point(64, 52, in: rect),
    options: []
  )
  context.restoreGState()

  context.setStrokeColor(color(0xB4D2FF, alpha: 0.55).cgColor)
  context.setLineWidth(max(1, rect.width * 0.008))
  context.setLineCap(.round)
  let sparkleLines = [
    (point(48, 16, in: rect), point(48, 22, in: rect)),
    (point(48, 50, in: rect), point(48, 56, in: rect)),
    (point(28, 36, in: rect), point(34, 36, in: rect)),
    (point(62, 36, in: rect), point(68, 36, in: rect)),
  ]
  for (start, end) in sparkleLines {
    context.move(to: start)
    context.addLine(to: end)
    context.strokePath()
  }
}

func drawAppIconBitmap(size: CGFloat) throws -> NSBitmapImageRep {
  try makeBitmap(size: size) { context, rect in
    context.interpolationQuality = .high
    context.translateBy(x: 0, y: rect.height)
    context.scaleBy(x: 1, y: -1)

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
      start: CGPoint(x: rect.minX, y: rect.minY),
      end: CGPoint(x: rect.maxX, y: rect.maxY),
      options: []
    )

    let cardInset = rect.width * 0.04
    let cardRect = rect.insetBy(dx: cardInset, dy: cardInset)
    let radius = rect.width * 0.20
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
      start: CGPoint(x: cardRect.minX, y: cardRect.minY),
      end: CGPoint(x: cardRect.maxX, y: cardRect.maxY),
      options: []
    )
    context.restoreGState()

    context.setStrokeColor(color(0xFFFFFF, alpha: 0.05).cgColor)
    context.setLineWidth(max(1, rect.width * 0.004))
    context.addPath(cardPath)
    context.strokePath()

    let iconRect = cardRect.insetBy(dx: cardRect.width * 0.04, dy: cardRect.height * 0.04)
    drawLogoGlyph(context, in: iconRect)
  }
}

func drawLaunchBitmap(size: CGFloat) throws -> NSBitmapImageRep {
  try makeBitmap(size: size) { context, rect in
    context.interpolationQuality = .high
    context.translateBy(x: 0, y: rect.height)
    context.scaleBy(x: 1, y: -1)

    let cardRect = rect.insetBy(dx: rect.width * 0.08, dy: rect.height * 0.08)
    let radius = rect.width * 0.18
    let cardPath = CGPath(
      roundedRect: cardRect,
      cornerWidth: radius,
      cornerHeight: radius,
      transform: nil
    )

    context.saveGState()
    context.setShadow(
      offset: CGSize(width: 0, height: rect.height * 0.05),
      blur: rect.width * 0.12,
      color: color(0x000000, alpha: 0.34).cgColor
    )
    context.addPath(cardPath)
    context.setFillColor(color(0x000000, alpha: 0.001).cgColor)
    context.fillPath()
    context.restoreGState()

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
      start: CGPoint(x: cardRect.minX, y: cardRect.minY),
      end: CGPoint(x: cardRect.maxX, y: cardRect.maxY),
      options: []
    )
    context.restoreGState()

    context.setStrokeColor(color(0xFFFFFF, alpha: 0.06).cgColor)
    context.setLineWidth(max(1, rect.width * 0.006))
    context.addPath(cardPath)
    context.strokePath()

    let iconRect = cardRect.insetBy(dx: cardRect.width * 0.04, dy: cardRect.height * 0.04)
    drawLogoGlyph(context, in: iconRect)
  }
}

func savePNG(_ bitmap: NSBitmapImageRep, to path: String) throws {
  guard let data = bitmap.representation(using: .png, properties: [:]) else {
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
  let bitmap = try drawAppIconBitmap(size: target.size)
  try savePNG(bitmap, to: target.path)
  print("Generated \(target.path)")
}

for target in launchTargets {
  let bitmap = try drawLaunchBitmap(size: target.size)
  try savePNG(bitmap, to: target.path)
  print("Generated \(target.path)")
}
