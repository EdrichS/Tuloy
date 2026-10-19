import AppKit
import SwiftUI

/// Tuloy's own symbol: an open ring, "it keeps going". Four versions of the one drawing,
/// for running, paused, resting and needs attention.
///
/// PROVISIONAL. This is the first pick from branding.txt's shortlist (the open ring), drawn so
/// the menu bar stops borrowing Apple's stock symbols. When the logo is chosen, redraw it here:
/// the menu bar, Help, Preferences and the app icon script (scripts/make-icon.swift) follow.
struct Glyph: View {
    var status: Engine.Status
    var size: CGFloat = 18

    /// The gap at the top right, in degrees (0 is 3 o'clock, -90 is 12 o'clock).
    static let gapStart = -72.0
    static let gapEnd = -18.0

    var body: some View {
        Canvas { context, canvas in
            let scale = canvas.width / 18
            let line = 1.9 * scale
            let center = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
            let radius = canvas.width / 2 - line / 2 - 1.2 * scale

            // The ring runs clockwise from the far side of the gap, all the way round, to its near side.
            var ring = Path()
            ring.addArc(center: center, radius: radius, startAngle: .degrees(Glyph.gapEnd),
                        endAngle: .degrees(Glyph.gapStart + 360), clockwise: false)
            context.stroke(ring, with: .foreground, style: StrokeStyle(lineWidth: line, lineCap: .round))

            let angle = Glyph.gapStart * .pi / 180
            let tip = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
            let box = { (x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) in
                CGRect(x: center.x + x * scale, y: center.y + y * scale, width: width * scale, height: height * scale)
            }

            switch status {
            case .running:
                // A dot at the leading end: on its way round.
                let dot = 4.4 * scale
                context.fill(Path(ellipseIn: CGRect(x: tip.x - dot / 2, y: tip.y - dot / 2, width: dot, height: dot)), with: .foreground)
            case .paused:
                for x in [-3.05, 1.15] {
                    context.fill(Path(roundedRect: box(x, -3.4, 1.9, 6.8), cornerRadius: 0.9 * scale), with: .foreground)
                }
            case .resting:
                // A small moon: the week is used up, so Tuloy sleeps until it resets.
                let moon = Path(ellipseIn: box(-3.6, -3.6, 7.2, 7.2))
                let bite = Path(ellipseIn: box(-1, -5.2, 7.2, 7.2))
                context.fill(moon.subtracting(bite), with: .foreground)
            case .problem:
                context.fill(Path(roundedRect: box(-1, -4.2, 2, 5.4), cornerRadius: scale), with: .foreground)
                context.fill(Path(ellipseIn: box(-1.15, 2.2, 2.3, 2.3)), with: .foreground)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    /// The menu bar version: a template image, which macOS draws in black or white to suit the menu bar.
    @MainActor
    static func image(for status: Engine.Status) -> NSImage {
        if let image = images[status] { return image }
        let renderer = ImageRenderer(content: Glyph(status: status).foregroundStyle(.black))
        renderer.scale = 2
        let image = renderer.nsImage ?? NSImage()
        image.isTemplate = true
        images[status] = image
        return image
    }

    @MainActor private static var images: [Engine.Status: NSImage] = [:]
}
