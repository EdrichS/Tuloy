import SwiftUI

/// The mini window: a small panel that floats above your other windows, on every desktop.
/// Close it whenever you like. Tuloy keeps running in the menu bar.
struct MiniWindow: View {
    let model: AppModel

    var body: some View {
        MiniContent(model: model)
            .floatingWindow(movableByBackground: true)
    }
}

struct MiniContent: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                StatusRing(model: model, size: 58)
                VStack(alignment: .leading, spacing: 2) {
                    Text(headline)
                        .font(.callout.weight(.semibold))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subline)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 6) {
                if model.attention != nil {
                    // Pinging won't work until this is fixed, so lead with the fix.
                    Button("Fix It…") { model.open(.main, tab: .connection) }
                        .buttonStyle(TuloyButtonStyle(prominent: true))
                        .help("Open Connection to see what's wrong")
                }
                Button(model.isPinging ? "Pinging…" : "Ping Now") {
                    Task { await model.pingNow() }
                }
                .buttonStyle(TuloyButtonStyle(prominent: model.attention == nil))
                .disabled(model.isPinging)
                .help("Start a window this minute")

                Button(model.isPaused ? "Resume" : "Pause") { model.togglePause() }
                    .buttonStyle(TuloyButtonStyle())
                    .help(model.isPaused ? "Start pinging again" : "No pings until you resume")

                Spacer(minLength: 0)

                Button {
                    model.open(.main, tab: model.attention == nil ? .home : .connection)
                } label: {
                    Image(systemName: "macwindow")
                }
                .buttonStyle(TuloyButtonStyle())
                .help("Open the Tuloy window")
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
        .padding(.top, 6)
        .frame(width: 280)
    }

    /// The window that's open, if things are running normally.
    private var openWindow: UsageReading? {
        guard model.status == .running else { return nil }
        return model.currentWindow
    }

    /// Shorter than the main window's line, to fit.
    private var headline: String {
        guard let openWindow else { return model.headline }
        return "Fresh at \(openWindow.isEstimate ? "about " : "")\(Format.time(openWindow.resetsAt))"
    }

    private var subline: String {
        guard let openWindow else { return model.detail }
        return "Resets in \(Format.duration(to: openWindow.resetsAt, from: model.now))"
    }
}
