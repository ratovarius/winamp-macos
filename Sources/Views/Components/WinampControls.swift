import SwiftUI

struct WinampButton: View {
    let icon: String
    let width: CGFloat
    let action: () -> Void
    @Environment(\.winampUIScale) private var uiScale

    var body: some View {
        WinampClassicTextButton(
            title: self.icon,
            scale: self.uiScale,
            minWidth: self.width,
            height: WinampMetrics.transportButtonHeight,
            action: self.action
        )
    }
}

struct WinampToggle: View {
    let text: String
    @Binding var isOn: Bool
    let width: CGFloat
    @Environment(\.winampUIScale) private var uiScale

    var body: some View {
        WinampClassicToggleButton(
            title: self.text,
            isOn: self.$isOn,
            width: self.width,
            scale: self.uiScale,
            height: WinampMetrics.smallButtonHeight
        )
    }
}
