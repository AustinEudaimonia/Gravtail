import Cocoa

protocol MenuBarIconDelegate: AnyObject {
    func menuBarIconPressed(from view: NSView)
}

enum HeavyCursorIconRenderer {
    private static let masterImage: NSImage? = {
        guard let url = Bundle.main.url(forResource: "HeavyCursorIconMaster", withExtension: "png") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }()

    static func makeImage(size: NSSize) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        draw(in: NSRect(origin: .zero, size: size), weight: 0)
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    static func draw(in rect: NSRect, weight: CGFloat) {
        // Use the selected artwork directly so the menu-bar mark is a faithful
        // reproduction of the approved reference rather than a redraw.
        if let masterImage {
            masterImage.draw(
                in: rect,
                from: NSRect(origin: .zero, size: masterImage.size),
                operation: .sourceOver,
                fraction: 1
            )
            return
        }

        drawFallback(in: rect, weight: weight)
    }

    private static func drawFallback(in rect: NSRect, weight: CGFloat) {
        // Keep a 24px hit target, but draw the mark as a compact 20px glyph so
        // it remains legible in the macOS menu bar and does not feel spread out.
        let scale = min(rect.width, rect.height) / 20
        let x = rect.minX + (rect.width - 20 * scale) / 2
        let y = rect.minY + (rect.height - 20 * scale) / 2
        let canvas = NSRect(x: x, y: y, width: 20 * scale, height: 20 * scale)
        let clampedWeight = max(0, min(1, weight))

        let pointer = NSBezierPath()
        pointer.move(to: CGPoint(x: canvas.minX + 5.3 * scale, y: canvas.maxY - 3.3 * scale))
        pointer.line(to: CGPoint(x: canvas.minX + 8.2 * scale, y: canvas.minY + 4.8 * scale))
        pointer.line(to: CGPoint(x: canvas.minX + 10.8 * scale, y: canvas.minY + 9.1 * scale))
        pointer.line(to: CGPoint(x: canvas.minX + 16.1 * scale, y: canvas.minY + 7.3 * scale))
        pointer.line(to: CGPoint(x: canvas.minX + 14.7 * scale, y: canvas.minY + 10.1 * scale))
        pointer.line(to: CGPoint(x: canvas.minX + 18 * scale, y: canvas.minY + 11.6 * scale))
        pointer.close()
        NSColor.black.withAlphaComponent(0.32).setStroke()
        pointer.lineWidth = 0.55 * scale
        NSColor.white.withAlphaComponent(0.96).setFill()
        pointer.fill()
        pointer.stroke()

        // The comet tail is the compact gravity cue: it starts thin at the
        // pointer, bends down-left, and gets heavier as the session progresses.
        let tail = NSBezierPath()
        tail.lineWidth = (0.95 + 0.95 * clampedWeight) * scale
        tail.lineCapStyle = .round
        tail.move(to: CGPoint(x: canvas.minX + 8.1 * scale, y: canvas.minY + 10.4 * scale))
        tail.curve(
            to: CGPoint(x: canvas.minX + (5.1 - 0.35 * clampedWeight) * scale, y: canvas.minY + (5.6 - 0.35 * clampedWeight) * scale),
            controlPoint1: CGPoint(x: canvas.minX + 6.9 * scale, y: canvas.minY + 9.2 * scale),
            controlPoint2: CGPoint(x: canvas.minX + (3.8 - 0.2 * clampedWeight) * scale, y: canvas.minY + 7.9 * scale)
        )
        tail.curve(
            to: CGPoint(x: canvas.minX + (6.0 + 0.25 * clampedWeight) * scale, y: canvas.minY + (4.0 - 0.35 * clampedWeight) * scale),
            controlPoint1: CGPoint(x: canvas.minX + (5.0 - 0.25 * clampedWeight) * scale, y: canvas.minY + 4.9 * scale),
            controlPoint2: CGPoint(x: canvas.minX + (5.8 + 0.1 * clampedWeight) * scale, y: canvas.minY + 4.2 * scale)
        )
        // A light outer edge keeps the compact gravity trail readable over a
        // dark menu bar; the darker inner stroke preserves the graphite look
        // over bright wallpaper.
        tail.lineWidth = (1.55 + 1.15 * clampedWeight) * scale
        NSColor.white.withAlphaComponent(0.62).setStroke()
        tail.stroke()
        tail.lineWidth = (0.86 + 0.82 * clampedWeight) * scale
        NSColor.black.withAlphaComponent(0.78).setStroke()
        tail.stroke()

        // A compact gravity center closes the curve. It grows only slightly;
        // most of the state change is expressed by the tail's thickness and sag.
        let wellWidth = (2.25 + 0.65 * clampedWeight) * scale
        let wellHeight = (1.55 + 0.35 * clampedWeight) * scale
        let well = NSRect(
            x: canvas.minX + (5.0 - 0.1 * clampedWeight) * scale,
            y: canvas.minY + (3.15 - 0.18 * clampedWeight) * scale,
            width: wellWidth,
            height: wellHeight
        )
        let wellPath = NSBezierPath(ovalIn: well)
        NSColor.black.withAlphaComponent(0.9).setFill()
        wellPath.fill()
        wellPath.lineWidth = 0.55 * scale
        NSColor.white.withAlphaComponent(0.58).setStroke()
        wellPath.stroke()

        let headSize = (2.4 + 0.55 * clampedWeight) * scale
        let head = NSRect(
            x: canvas.minX + 15.4 * scale - headSize / 2,
            y: canvas.minY + 16.0 * scale - headSize / 2,
            width: headSize,
            height: headSize
        )
        NSColor(srgbRed: 1, green: 0.63 + 0.08 * clampedWeight, blue: 0.28, alpha: 1).setFill()
        NSBezierPath(ovalIn: head).fill()
    }
}

/// A small, explicit menu-bar control. NSStatusItem is normally the right
/// primitive for a menu-bar app, but macOS can move a status item into the
/// overflow area (or omit it while a full-screen menu bar is hidden). This
/// view gives Gravtail one deterministic, clickable mark at the top center of
/// the active screen instead of leaving the user with no way to open settings.
final class MenuBarIconView: NSView {
    weak var delegate: MenuBarIconDelegate?
    var weightProvider: () -> CGFloat = { 0 }

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        HeavyCursorIconRenderer.draw(in: bounds.insetBy(dx: 4, dy: 4), weight: weightProvider())
    }

    override func mouseDown(with event: NSEvent) {
        delegate?.menuBarIconPressed(from: self)
    }

    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityLabel() -> String? { "Gravtail settings" }
    override func accessibilityHelp() -> String? { "Open Gravtail settings" }
}
