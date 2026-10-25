import AppKit

/// Draws the menu-bar glyph: a small headphones symbol followed by a battery whose
/// fill tracks the charge level. The image is a template, so it adapts to light and
/// dark menu bars.
enum BatteryIcon {
    static let size = NSSize(width: 46, height: 14)

    private static let headphonesWidth: CGFloat = 15
    private static let gap: CGFloat = 4

    static func image(level: Int?) -> NSImage {
        let image = NSImage(size: size, flipped: false) { _ in
            drawHeadphones(in: NSRect(x: 0, y: 0, width: headphonesWidth, height: size.height))
            drawBattery(level: level, originX: headphonesWidth + gap)
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func drawHeadphones(in rect: NSRect) {
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        if let symbol = NSImage(systemSymbolName: "headphones", accessibilityDescription: nil)?
            .withSymbolConfiguration(config) {
            let s = symbol.size
            let target = NSRect(x: rect.midX - s.width / 2,
                                y: rect.midY - s.height / 2,
                                width: s.width, height: s.height)
            symbol.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1)
            return
        }
        // Fallback if the symbol is unavailable: a simple arc with two ear cups.
        let arc = NSBezierPath()
        arc.appendArc(withCenter: NSPoint(x: rect.midX, y: rect.midY - 1), radius: 5.5, startAngle: 180, endAngle: 0, clockwise: true)
        arc.lineWidth = 1.5
        NSColor.black.setStroke()
        arc.stroke()
        NSColor.black.setFill()
        NSBezierPath(roundedRect: NSRect(x: rect.midX - 7, y: rect.midY - 5, width: 3, height: 5), xRadius: 1, yRadius: 1).fill()
        NSBezierPath(roundedRect: NSRect(x: rect.midX + 4, y: rect.midY - 5, width: 3, height: 5), xRadius: 1, yRadius: 1).fill()
    }

    private static func drawBattery(level: Int?, originX: CGFloat) {
        let bodyRect = NSRect(x: originX + 0.5, y: 1.5, width: 23, height: 11)
        let body = NSBezierPath(roundedRect: bodyRect, xRadius: 3, yRadius: 3)
        body.lineWidth = 1
        NSColor.black.withAlphaComponent(0.55).setStroke()
        body.stroke()

        let nub = NSBezierPath(roundedRect: NSRect(x: bodyRect.maxX + 1, y: bodyRect.midY - 2, width: 2, height: 4), xRadius: 1, yRadius: 1)
        NSColor.black.withAlphaComponent(0.55).setFill()
        nub.fill()

        if let level {
            let clamped = CGFloat(min(max(level, 0), 100))
            let inner = bodyRect.insetBy(dx: 2, dy: 2)
            let width = max(1.5, inner.width * clamped / 100)
            let fillRect = NSRect(x: inner.minX, y: inner.minY, width: width, height: inner.height)
            NSColor.black.setFill()
            NSBezierPath(roundedRect: fillRect, xRadius: 1.5, yRadius: 1.5).fill()
        } else {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 9, weight: .heavy),
                .foregroundColor: NSColor.black,
            ]
            let mark = NSAttributedString(string: "?", attributes: attrs)
            let markSize = mark.size()
            mark.draw(at: NSPoint(x: bodyRect.midX - markSize.width / 2,
                                  y: bodyRect.midY - markSize.height / 2))
        }
    }
}
