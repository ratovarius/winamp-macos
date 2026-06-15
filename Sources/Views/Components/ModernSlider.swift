import SwiftUI

// MARK: - Volume (left → right, green at low → red at high)

struct WinampVolumeSlider: View {
    @Binding var value: Double
    var scale: CGFloat = 1.0
    @State private var isDragging = false

    var body: some View {
        GeometryReader { geometry in
            let percent = CGFloat((value - 0) / 1)
            let fillColor = WinampColors.levelColor(normalized: percent)
            let thumbSize = 10 * scale
            let handleX = max(0, (geometry.size.width - thumbSize) * percent)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2 * scale)
                    .fill(Color.black)
                    .overlay(
                        RoundedRectangle(cornerRadius: 2 * scale)
                            .strokeBorder(WinampColors.borderDark, lineWidth: 1)
                    )

                if percent > 0.01 {
                    RoundedRectangle(cornerRadius: 2 * scale)
                        .fill(fillColor)
                        .frame(width: max(thumbSize * 0.5, geometry.size.width * percent))
                }

                WinampSliderThumb(scale: scale)
                    .offset(x: handleX)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        self.isDragging = true
                        let percent = Double(drag.location.x / geometry.size.width)
                        self.value = min(max(percent, 0), 1)
                    }
                    .onEnded { _ in
                        self.isDragging = false
                    }
            )
        }
    }
}

// MARK: - Balance (center = neutral, fills left or right)

struct WinampBalanceSlider: View {
    @Binding var value: Double
    var scale: CGFloat = 1.0
    @State private var isDragging = false

    var body: some View {
        GeometryReader { geometry in
            let centerX = geometry.size.width / 2
            let thumbSize = 10 * scale
            let handleX = centerX + (geometry.size.width / 2 - thumbSize / 2) * CGFloat(value)
            let fillExtent = abs(CGFloat(value)) * (geometry.size.width / 2)
            let fillColor = WinampColors.levelColor(normalized: 0.5 + abs(CGFloat(value)) * 0.5)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2 * scale)
                    .fill(Color.black)
                    .overlay(
                        RoundedRectangle(cornerRadius: 2 * scale)
                            .strokeBorder(WinampColors.borderDark, lineWidth: 1)
                    )

                if fillExtent > 0.5 {
                    RoundedRectangle(cornerRadius: 1 * scale)
                        .fill(fillColor)
                        .frame(width: fillExtent, height: geometry.size.height - 2 * scale)
                        .offset(
                            x: value < 0 ? centerX - fillExtent : centerX,
                            y: 1 * scale
                        )
                }

                // Center tick
                Rectangle()
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 1, height: geometry.size.height - 2 * scale)
                    .offset(x: centerX - 0.5, y: 1 * scale)

                WinampSliderThumb(scale: scale)
                    .offset(x: handleX - thumbSize / 2)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        self.isDragging = true
                        let percent = Double((drag.location.x / geometry.size.width - 0.5) * 2)
                        self.value = min(max(percent, -1), 1)
                    }
                    .onEnded { _ in
                        self.isDragging = false
                    }
            )
        }
    }
}

// MARK: - Shared horizontal thumb

private struct WinampSliderThumb: View {
    let scale: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2 * scale)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.82, green: 0.84, blue: 0.88),
                            Color(red: 0.58, green: 0.62, blue: 0.68),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 10 * scale, height: 8 * scale)
                .overlay(
                    RoundedRectangle(cornerRadius: 2 * scale)
                        .strokeBorder(Color.black.opacity(0.5), lineWidth: 1)
                )

            Rectangle()
                .fill(Color.black.opacity(0.5))
                .frame(width: 6 * scale, height: 1)
        }
    }
}

// Legacy alias used elsewhere if needed.
struct ModernSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let color: Color
    var scale: CGFloat = 1.0

    var body: some View {
        WinampVolumeSlider(
            value: Binding(
                get: {
                    let span = self.range.upperBound - self.range.lowerBound
                    guard span > 0 else { return 0 }
                    return (self.value - self.range.lowerBound) / span
                },
                set: { normalized in
                    self.value = self.range.lowerBound + (self.range.upperBound - self.range.lowerBound) * normalized
                }
            ),
            scale: scale
        )
    }
}

struct ModernToggleButtonWithLight: View {
    let text: String
    @Binding var isOn: Bool
    var scale: CGFloat = 1.0

    var body: some View {
        Button(action: { self.isOn.toggle() }) {
            ZStack(alignment: .topTrailing) {
                Text(self.text)
                    .winampFont(size: 8, weight: .bold, scale: self.scale)
                    .foregroundColor(.white.opacity(0.9))
                    .frame(width: 24, height: 20)

                Rectangle()
                    .fill(self.isOn ? WinampColors.displayText : Color.black)
                    .frame(width: 5, height: 5)
                    .shadow(color: self.isOn ? WinampColors.displayText : Color.clear, radius: 3, x: 0, y: 0)
                    .offset(x: -3, y: 3)
            }
            .frame(width: 24, height: 20)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(red: 0.22, green: 0.25, blue: 0.32))

                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.4),
                                    Color.white.opacity(0.2),
                                    Color.black.opacity(0.2),
                                    Color.black.opacity(0.5),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(Color.black.opacity(0.5), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.3), radius: 1, x: 0, y: 1)
        }
        .buttonStyle(.plain)
    }
}
