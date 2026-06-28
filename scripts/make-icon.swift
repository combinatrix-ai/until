#!/usr/bin/env swift
import AppKit

// Renders the Until app icon (green squircle + white dot/chevron) into an
// .iconset and packs it into scripts/Until.icns via iconutil. Geometry mirrors
// Sources/Until/BrandIcon.swift. Run: swift scripts/make-icon.swift

let root = URL(fileURLWithPath: CommandLine.arguments.first ?? "")
  .deletingLastPathComponent().deletingLastPathComponent()
let scripts = root.appendingPathComponent("scripts")
let iconset = scripts.appendingPathComponent("Until.iconset")
let icns = scripts.appendingPathComponent("Until.icns")

let green = NSColor(srgbRed: 0x1D / 255.0, green: 0x9E / 255.0, blue: 0x75 / 255.0, alpha: 1)

func render(_ size: Int) -> Data {
  let dim = CGFloat(size)
  let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
  )!
  rep.size = NSSize(width: dim, height: dim)
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

  let margin = dim * 0.085
  let backgroundRect = NSRect(x: margin, y: margin, width: dim - margin * 2, height: dim - margin * 2)
  let radius = backgroundRect.width * 0.2237
  green.setFill()
  NSBezierPath(roundedRect: backgroundRect, xRadius: radius, yRadius: radius).fill()

  // Glyph in a 24×24 space, optically centred (bbox spans x≈4.4..17.5).
  let scale = backgroundRect.width / 24.0 * 0.86
  let originX = backgroundRect.midX - 10.95 * scale
  let originY = backgroundRect.midY - 12 * scale
  func point(_ designX: CGFloat, _ designY: CGFloat) -> NSPoint {
    NSPoint(x: originX + designX * scale, y: originY + (24 - designY) * scale)
  }
  NSColor.white.setFill()
  NSColor.white.setStroke()
  let dotRadius = 2.6 * scale
  let dotCenter = point(7, 12)
  NSBezierPath(
    ovalIn: NSRect(
      x: dotCenter.x - dotRadius,
      y: dotCenter.y - dotRadius,
      width: dotRadius * 2,
      height: dotRadius * 2
    )
  ).fill()
  let chevron = NSBezierPath()
  chevron.lineWidth = 2.4 * scale
  chevron.lineCapStyle = .round
  chevron.lineJoinStyle = .round
  chevron.move(to: point(12.5, 7))
  chevron.line(to: point(17.5, 12))
  chevron.line(to: point(12.5, 17))
  chevron.stroke()

  NSGraphicsContext.restoreGraphicsState()
  return rep.representation(using: .png, properties: [:])!
}

let fileManager = FileManager.default
try? fileManager.removeItem(at: iconset)
try fileManager.createDirectory(at: iconset, withIntermediateDirectories: true)

let specs: [(String, Int)] = [
  ("icon_16x16", 16), ("icon_16x16@2x", 32),
  ("icon_32x32", 32), ("icon_32x32@2x", 64),
  ("icon_128x128", 128), ("icon_128x128@2x", 256),
  ("icon_256x256", 256), ("icon_256x256@2x", 512),
  ("icon_512x512", 512), ("icon_512x512@2x", 1024)
]
for (name, size) in specs {
  try render(size).write(to: iconset.appendingPathComponent("\(name).png"))
}

let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
proc.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try proc.run()
proc.waitUntilExit()
try? fileManager.removeItem(at: iconset)
print(icns.path)
