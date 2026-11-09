import AppKit
import Sub2APIStatusCore

struct MenuBarUsageLevels: Equatable {
    let daily: Double?
    let weekly: Double?

    init(snapshot: MonitorSnapshot) {
        let subscriptions = snapshot.subscriptionSummary?.subscriptions ?? []
        daily = subscriptions.compactMap(\.dailyProgress).max()
        weekly = subscriptions.compactMap(\.weeklyProgress).max()
    }
}

@MainActor
enum MenuBarMeterImage {
    private static let imageSize = NSSize(width: 18, height: 18)
    private static let templateInk = NSColor.black

    static func make(
        levels: MenuBarUsageLevels,
        connected: Bool,
        display: MenuBarUsageDisplay
    ) -> NSImage {
        let image = NSImage(size: imageSize, flipped: false) { _ in
            NSGraphicsContext.current?.shouldAntialias = true

            drawBar(rect: NSRect(x: 1.5, y: 9.5, width: 15, height: 6), usage: levels.daily, connected: connected, display: display)
            drawBar(rect: NSRect(x: 1.5, y: 2.5, width: 15, height: 4), usage: levels.weekly, connected: connected, display: display)

            if !connected {
                let slash = NSBezierPath()
                slash.move(to: NSPoint(x: 3, y: 3))
                slash.line(to: NSPoint(x: 15, y: 15))
                slash.lineWidth = 1.5
                slash.lineCapStyle = .round
                templateInk.setStroke()
                slash.stroke()
            }

            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = accessibilityDescription(connected: connected, display: display)
        return image
    }

    private static func drawBar(
        rect: NSRect,
        usage: Double?,
        connected: Bool,
        display: MenuBarUsageDisplay
    ) {
        let ink = templateInk
        let radius = rect.height / 2
        let track = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

        ink.withAlphaComponent(0.24).setFill()
        track.fill()

        let strokeRect = rect.insetBy(dx: 0.5, dy: 0.5)
        let outline = NSBezierPath(
            roundedRect: strokeRect,
            xRadius: max(radius - 0.5, 0),
            yRadius: max(radius - 0.5, 0)
        )
        outline.lineWidth = 1
        ink.withAlphaComponent(0.44).setStroke()
        outline.stroke()

        guard connected, let usage else {
            return
        }

        let used = min(max(usage, 0), 1)
        let filled = display == .remaining ? 1 - used : used
        guard filled > 0 else {
            return
        }

        if filled >= 1 {
            ink.setFill()
            track.fill()
            return
        }

        let fillWidth = rect.width * filled

        NSGraphicsContext.current?.cgContext.saveGState()
        track.addClip()
        ink.setFill()
        NSBezierPath(rect: NSRect(x: rect.minX, y: rect.minY, width: min(fillWidth, rect.width), height: rect.height)).fill()
        NSGraphicsContext.current?.cgContext.restoreGState()
    }

    private static func accessibilityDescription(
        connected: Bool,
        display: MenuBarUsageDisplay
    ) -> String {
        guard connected else {
            return "Sub2API disconnected"
        }
        return "Sub2API \(display.displayName.lowercased()) quota, daily + weekly"
    }
}
