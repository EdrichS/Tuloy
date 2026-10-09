import SwiftUI

/// The mini window: the panel, floating above your other windows, on every desktop.
/// Close it whenever you like. Tuloy keeps running in the menu bar.
struct MiniWindow: View {
    let model: AppModel

    var body: some View {
        PanelContent(model: model, place: .mini)
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
            .padding(.top, 6)
            .frame(width: 300)
            .floatingWindow(movableByBackground: true)
    }
}
