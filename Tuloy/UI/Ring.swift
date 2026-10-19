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
            Circle().inset(by: 0.9).stroke(lineWidth: 1.8).opacity(0.3)
            Circle().inset(by: 0.9).trim(from: 0, to: min(1, max(0, progress)))
                .stroke(style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                .rotationEffect(.degrees(-90))   // start at 12 o'clock
            label
        }
        .foregroundStyle(.black)
        .opacity(isFaded ? 0.5 : 1)
        .frame(width: 21, height: 21)
    }

    /// As big as the ring allows: two characters large, three narrower, and "5h" with a small "h".
    @ViewBuilder
    private var label: some View {
        if text.count >= 2, text.count <= 3, text.hasSuffix("h"), text.dropLast().allSatisfy(\.isNumber) {
            let digits = text.count - 1
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(text.dropLast())
                    .font(.system(size: digits == 1 ? 11.5 : 9.5, weight: .bold, design: .rounded))
                Text("h")
                    .font(.system(size: digits == 1 ? 7.5 : 6, weight: .bold, design: .rounded))
            }
        } else if text.count >= 3 {
            Text(text)
                .font(.system(size: text.count == 3 ? 9.5 : 7.5, weight: .bold).width(.condensed))
                .tracking(-0.4)
        } else {
            Text(text)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
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
