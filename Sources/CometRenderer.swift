import Cocoa

struct TrailPoint {
    let position: CGPoint
    let time: CFTimeInterval
}

final class CometModel {
    static let shared = CometModel()

    private(set) var points: [TrailPoint] = []
    private var lastPosition: CGPoint?

    func tick(weight: CGFloat, now: CFTimeInterval) {
        let location = NSEvent.mouseLocation
        let distance = hypot(
            location.x - (lastPosition?.x ?? location.x - 1),
            location.y - (lastPosition?.y ?? location.y - 1)
        )

        if lastPosition == nil || distance > 0.5 {
            points.append(TrailPoint(position: location, time: now))
            lastPosition = location
        }

        let lifetime = Self.lifetime(for: weight)
        points.removeAll { now - $0.time > lifetime }
    }

    func clear() {
        points.removeAll()
        lastPosition = nil
    }

    static func lifetime(for weight: CGFloat) -> TimeInterval {
        0.16 + 1.84 * Double(weight)
    }

    static func thickness(for weight: CGFloat) -> CGFloat {
        2 + 15 * weight
    }
}

final class CometView: NSView {
    var screenOrigin = CGPoint.zero
    var weightProvider: () -> CGFloat = { 0 }

    private func local(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x - screenOrigin.x, y: point.y - screenOrigin.y)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        let weight = weightProvider()
        guard weight > 0.005 else { return }

        let points = CometModel.shared.points
        guard let head = points.last else { return }

        let now = CACurrentMediaTime()
        let lifetime = CometModel.lifetime(for: weight)
        let thickness = CometModel.thickness(for: weight)
        let color = cometColor(weight: weight)

        context.setLineCap(.round)
        context.setLineJoin(.round)

        let passes: [(width: CGFloat, alpha: CGFloat, white: CGFloat)] = [
            (2.6, 0.13, 0.00),
            (1.35, 0.34, 0.10),
            (0.56, 0.82, 0.52),
        ]

        if points.count > 1 {
            for pass in passes {
                for index in 1..<points.count {
                    let previous = points[index - 1]
                    let current = points[index]
                    let age = max(0, now - current.time)
                    let life = CGFloat(max(0, 1 - age / lifetime))
                    guard life > 0.01 else { continue }

                    let ageProgress = CGFloat(min(1, age / lifetime))
                    let sag = weight * 60 * ageProgress * ageProgress
                    let start = local(previous.position)
                    let end = local(current.position)

                    let passColor = color.blended(withFraction: pass.white, of: .white) ?? color
                    context.setStrokeColor(passColor.withAlphaComponent(life * pass.alpha * weight).cgColor)
                    context.setLineWidth(max(0.5, thickness * pass.width * life * life))
                    context.move(to: CGPoint(x: start.x, y: start.y - sag))
                    context.addLine(to: CGPoint(x: end.x, y: end.y - sag))
                    context.strokePath()
                }
            }
        }

        let center = local(head.position)
        for (radius, alpha, white) in [
            (thickness * 2.0, 0.14, 0.0),
            (thickness * 1.05, 0.38, 0.2),
            (thickness * 0.48, 0.86, 0.7),
        ] as [(CGFloat, CGFloat, CGFloat)] {
            let headColor = color.blended(withFraction: white, of: .white) ?? color
            context.setFillColor(headColor.withAlphaComponent(alpha * weight).cgColor)
            context.fillEllipse(in: CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            ))
        }
    }

    private func cometColor(weight: CGFloat) -> NSColor {
        let light = NSColor(srgbRed: 0.50, green: 0.82, blue: 0.95, alpha: 1)
        let heavy = NSColor(srgbRed: 0.95, green: 0.55, blue: 0.24, alpha: 1)
        return light.blended(withFraction: weight, of: heavy) ?? light
    }
}
