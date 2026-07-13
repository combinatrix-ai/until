import AppKit

/// The Until brand mark: a dot ("now") with a chevron pointing to what's next.
/// Drawn in code so the menubar glyph and in-app header share one source of
/// truth, and the same geometry backs the generated app icon (scripts/make-icon.swift).
enum BrandIcon {
  /// Monochrome template image for the menubar status item.
  static func menubarImage(size: CGFloat = 18, trailingCanvasTrim: CGFloat = 0) -> NSImage {
    let canvasWidth = max(1, size - trailingCanvasTrim)
    let image = NSImage(size: NSSize(width: canvasWidth, height: size), flipped: false) { _ in
      draw(in: NSRect(x: 0, y: 0, width: size, height: size), color: .black)
      return true
    }
    image.isTemplate = true
    return image
  }

  /// Renders the dot + chevron into `rect`, mapped from a 24×24 design space.
  static func draw(in rect: NSRect, color: NSColor) {
    let scale = rect.width / 24.0
    func point(_ designX: CGFloat, _ designY: CGFloat) -> NSPoint {
      NSPoint(x: rect.minX + designX * scale, y: rect.minY + (24 - designY) * scale)
    }
    color.setFill()
    color.setStroke()

    let radius = 2.6 * scale
    let center = point(7, 12)
    NSBezierPath(
      ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    ).fill()

    let chevron = NSBezierPath()
    chevron.lineWidth = 2 * scale
    chevron.lineCapStyle = .round
    chevron.lineJoinStyle = .round
    chevron.move(to: point(12.5, 7))
    chevron.line(to: point(17.5, 12))
    chevron.line(to: point(12.5, 17))
    chevron.stroke()
  }
}
