import SwiftUI

enum WinampUIScaleLevel: CGFloat, CaseIterable, Identifiable {
    case standard = 1.0
    case large = 1.25
    case extraLarge = 1.5
    case huge = 2.0

    var id: CGFloat { rawValue }

    var label: String {
        switch self {
        case .standard: "100%"
        case .large: "125%"
        case .extraLarge: "150%"
        case .huge: "200%"
        }
    }
}

@MainActor
final class WinampUIScale: ObservableObject {
    static let shared = WinampUIScale()
    static let basePanelWidth: CGFloat = WinampMetrics.panelWidth
    static let baseMainPlayerHeight: CGFloat = WinampMetrics.mainPlayerHeight
    private static let userDefaultsKey = "WinampUIScale"

    @Published private(set) var level: WinampUIScaleLevel

    var scale: CGFloat { level.rawValue }
    var panelWidth: CGFloat { Self.basePanelWidth * scale }

    func size(_ points: CGFloat) -> CGFloat { points * scale }

    private init() {
        let saved = UserDefaults.standard.double(forKey: Self.userDefaultsKey)
        if let level = WinampUIScaleLevel(rawValue: CGFloat(saved)) {
            self.level = level
        } else {
            self.level = .standard
        }
    }

    func setLevel(_ level: WinampUIScaleLevel) {
        self.level = level
        UserDefaults.standard.set(level.rawValue, forKey: Self.userDefaultsKey)
    }
}

private struct WinampUIScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1.0
}

extension EnvironmentValues {
    var winampUIScale: CGFloat {
        get { self[WinampUIScaleKey.self] }
        set { self[WinampUIScaleKey.self] = newValue }
    }
}

extension View {
    func winampFont(
        size: CGFloat,
        weight: Font.Weight = .regular,
        design _: Font.Design = .default,
        scale: CGFloat
    ) -> some View {
        font(WinampTypography.font(size: size * scale, weight: weight))
    }
}
