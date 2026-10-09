import AppKit
import SwiftUI

/// A small progress ring with text inside, sized for the menu bar.
struct Ring: View {
    var progress: Double   // 0...1
    var text: String
    /// True when the number is more than 15 minutes old.
    var isFaded = false

    var body: some View {
        ZStack {
            Circle().inset(by: 1).stroke(lineWidth: 2).opacity(0.3)
            Circle().inset(by: 1).trim(from: 0, to: min(1, max(0, progress)))
                .stroke(style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))   // start at 12 o'clock
            Text(text)
                // Longer text ("4:59", "100") gets a narrower face so it stays inside the ring.
                .font(text.count <= 2
                      ? .system(size: 9, weight: .bold, design: .rounded)
                      : .system(size: 7.5, weight: .bold).width(.compressed))
                .monospacedDigit()
        }
        .foregroundStyle(.black)
        .opacity(isFaded ? 0.5 : 1)
        .frame(width: 20, height: 20)
    }

    /// Draws the ring as a template image, so macOS colors it for light and dark menu bars.
    @MainActor
    func image() -> NSImage {
        let renderer = ImageRenderer(content: self)
        renderer.scale = 2
        let image = renderer.nsImage ?? NSImage()
        image.isTemplate = true
        return image
    }
}
