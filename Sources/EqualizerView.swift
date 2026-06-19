import SwiftUI

private enum EQLayout {
    static let dbScaleWidth: CGFloat = 35
    static let preampWidth: CGFloat = 25
    static let columnGap: CGFloat = 4
    static let sliderHeight: CGFloat = 90
    static let graphHeight: CGFloat = 48
    static let horizontalPadding: CGFloat = 12
    static let toggleWidthON: CGFloat = 22
    static let toggleWidthAUTO: CGFloat = 36
    static let toggleHeight: CGFloat = 11
    static let eqButtonHeight: CGFloat = 11
}

struct EqualizerView: View {
    @EnvironmentObject var audioPlayer: AudioPlayer
    @Environment(\.winampUIScale) private var uiScale

    private var s: CGFloat { uiScale }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 3 * s) {
                HStack(spacing: 3 * s) {
                    Image(systemName: "waveform")
                        .winampFont(size: 8, weight: .bold, scale: s)
                        .foregroundColor(.white)
                        .frame(width: 10 * s, height: 10 * s)

                    Text("Winamp Equalizer")
                        .winampFont(size: 10, scale: s)
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 4 * s)
                .background(WinampColors.titleBar)

                Spacer()
            }
            .padding(.horizontal, 6 * s)
            .frame(height: WinampMetrics.titleBarHeight * s)
            .frame(maxWidth: .infinity)
            .background(WinampTitleBarBackground())
            .overlay(alignment: .leading) {
                PanelTitleBarDragOverlay()
            }

            VStack(spacing: 4 * s) {
                // Curve row: ON/AUTO in left column, graph above bands, PRESETS on right.
                HStack(alignment: .center, spacing: 0) {
                    VStack(spacing: 2 * s) {
                        WinampClassicToggleButton(
                            title: "ON",
                            isOn: Binding(
                                get: { self.audioPlayer.eqEnabled },
                                set: { self.audioPlayer.setEQEnabled($0) }
                            ),
                            width: EQLayout.toggleWidthON,
                            scale: s,
                            height: EQLayout.toggleHeight
                        )
                        WinampClassicToggleButton(
                            title: "AUTO",
                            isOn: Binding(
                                get: { self.audioPlayer.eqAutoEnabled },
                                set: { self.audioPlayer.setEQAutoEnabled($0) }
                            ),
                            width: EQLayout.toggleWidthAUTO,
                            scale: s,
                            height: EQLayout.toggleHeight
                        )
                    }
                    .frame(width: EQLayout.dbScaleWidth * s, alignment: .leading)
                    .padding(.trailing, EQLayout.columnGap * s)

                    Color.clear
                        .frame(width: (EQLayout.preampWidth + EQLayout.columnGap) * s)

                    FrequencyResponseGraph(
                        bandValues: self.audioPlayer.eqBandValues,
                        preampValue: self.audioPlayer.eqPreampValue,
                        lineWidth: max(3.0, 4.0 * s)
                    )
                    .frame(height: EQLayout.graphHeight * s)
                    .frame(maxWidth: .infinity)

                    Menu {
                        ForEach(self.audioPlayer.eqPresets()) { preset in
                            Button(preset.name) {
                                self.audioPlayer.applyEQPreset(preset)
                            }
                        }
                        Divider()
                        Button("Load EQF…") {
                            self.audioPlayer.importEQFPresets()
                        }
                    } label: {
                        Text("PRESETS")
                            .winampFont(size: 8, weight: .bold, scale: s)
                            .foregroundColor(Color(red: 0.12, green: 0.13, blue: 0.18))
                            .lineLimit(1)
                            .padding(.horizontal, 6 * s)
                            .frame(height: (EQLayout.eqButtonHeight + 2) * s)
                            .frame(minWidth: 52 * s)
                            .background(SilverBevel(isPressed: false))
                    }
                    .menuStyle(.borderlessButton)
                    .padding(.leading, 4 * s)
                }
                .padding(.horizontal, EQLayout.horizontalPadding * s)
                .padding(.top, 4 * s)

                HStack(alignment: .top, spacing: 0) {
                    VStack(spacing: 0) {
                        Text("+12db")
                            .winampFont(size: 8, design: .monospaced, scale: s)
                            .foregroundColor(WinampColors.displayText)
                        Spacer()
                        Text("+0db")
                            .winampFont(size: 8, design: .monospaced, scale: s)
                            .foregroundColor(WinampColors.displayText)
                        Spacer()
                        Text("-12db")
                            .winampFont(size: 8, design: .monospaced, scale: s)
                            .foregroundColor(WinampColors.displayText)
                        Spacer().frame(height: 12 * s)
                    }
                    .frame(width: EQLayout.dbScaleWidth * s, height: (EQLayout.sliderHeight + 12) * s)
                    .padding(.trailing, EQLayout.columnGap * s)

                    VStack(spacing: 2 * s) {
                        ClassicEQSlider(
                            value: Binding(
                                get: { self.audioPlayer.eqPreampValue },
                                set: { self.audioPlayer.setEQPreamp($0) }
                            ),
                            height: EQLayout.sliderHeight * s,
                            scale: s
                        )

                        Text("PREAMP")
                            .winampFont(size: 7, weight: .bold, design: .monospaced, scale: s)
                            .foregroundColor(WinampColors.displayText)
                            .fixedSize()
                    }
                    .frame(width: EQLayout.preampWidth * s)

                    Spacer(minLength: EQLayout.columnGap * s)

                    HStack(alignment: .top, spacing: 0) {
                        ForEach(0 ..< WinampEQBands.bandCount, id: \.self) { index in
                            VStack(spacing: 2 * s) {
                                ClassicEQSlider(
                                    value: Binding(
                                        get: { self.audioPlayer.eqBandValues[index] },
                                        set: { newValue in
                                            self.audioPlayer.setEQBand(index, gain: newValue * 12)
                                        }
                                    ),
                                    height: EQLayout.sliderHeight * s,
                                    scale: s
                                )

                                Text(WinampEQBands.displayLabels[index])
                                    .winampFont(size: 8, design: .monospaced, scale: s)
                                    .foregroundColor(WinampColors.displayText)
                            }
                            .frame(maxWidth: .infinity)

                            if index < WinampEQBands.bandCount - 1 {
                                Spacer(minLength: 1 * s)
                            }
                        }
                    }
                }
                .padding(.horizontal, EQLayout.horizontalPadding * s)
                .padding(.vertical, 8 * s)
                .background(WinampColors.mainBgDark)

                HStack {
                    Spacer()
                    WinampClassicTextButton(
                        title: "RESET",
                        scale: s,
                        minWidth: 36,
                        height: EQLayout.eqButtonHeight,
                        action: { self.audioPlayer.resetEQ() }
                    )
                }
                .padding(.horizontal, 8 * s)
                .padding(.bottom, 4 * s)
            }
            .background(WinampColors.mainBg)
        }
        .frame(width: WinampUIScale.basePanelWidth * s)
        .background(WinampColors.mainBgDark)
    }
}

// MARK: - Classic EQ Vertical Slider

struct ClassicEQSlider: View {
    @Binding var value: Float
    let height: CGFloat
    var scale: CGFloat = 1.0

    private var trackWidth: CGFloat { 14 * scale }
    private var thumbWidth: CGFloat { 18 * scale }
    private var thumbHeight: CGFloat { 11 * scale }

    var body: some View {
        GeometryReader { _ in
            // Thumb travels the full track; fill rises from the bottom to the thumb.
            let progress = (CGFloat(self.value) + 1) / 2 // 0…1 bottom→top
            let usable = self.height - self.thumbHeight
            let thumbY = (0.5 - progress) * usable // centered coords
            let fillHeight = max(0, progress * self.height)

            ZStack(alignment: .center) {
                // Recessed black channel
                Rectangle()
                    .fill(Color.black)
                    .frame(width: self.trackWidth, height: self.height)
                    .overlay(
                        Rectangle().strokeBorder(Color.black.opacity(0.9), lineWidth: 1)
                    )

                // Solid bar rising from the bottom, colored by the slider's value
                // (green at the bottom of travel → red at the top), as in classic Winamp.
                let fillColor = WinampColors.levelColor(normalized: progress)
                VStack {
                    Spacer(minLength: 0)
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [fillColor, fillColor.opacity(0.78)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: self.trackWidth - 3 * scale, height: max(0, fillHeight - 2 * scale))
                }
                .frame(width: self.trackWidth, height: self.height)
                .clipped()

                // Chunky silver thumb with a dark center groove
                ZStack {
                    RoundedRectangle(cornerRadius: 1.5 * scale)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.92, green: 0.94, blue: 0.97),
                                    Color(red: 0.70, green: 0.73, blue: 0.79),
                                    Color(red: 0.82, green: 0.85, blue: 0.90),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: self.thumbWidth, height: self.thumbHeight)
                        .overlay(
                            RoundedRectangle(cornerRadius: 1.5 * scale)
                                .strokeBorder(Color.black.opacity(0.5), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.4), radius: 0.5, x: 0, y: 1)

                    Rectangle()
                        .fill(Color.black.opacity(0.45))
                        .frame(width: self.thumbWidth * 0.6, height: 2 * scale)
                }
                .offset(y: thumbY)
            }
            .frame(width: self.thumbWidth, height: self.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let p = 1 - (gesture.location.y / self.height)
                        self.value = Float(max(0, min(1, p)) * 2 - 1)
                    }
            )
        }
        .frame(width: self.thumbWidth, height: self.height)
    }
}

// MARK: - Frequency Response Graph

struct FrequencyResponseGraph: View {
    let bandValues: [Float]
    let preampValue: Float
    var lineWidth: CGFloat = 2.0

    /// Stops for the vertical green→red gradient that colors the response curve by
    /// height. Sampled from `WinampColors.levelColor` at its 0.45 / 0.72 break points
    /// (plus a few midpoints) so a single gradient stroke reproduces the former
    /// per-segment coloring. `location` runs top→bottom, so level = 1 − location.
    private static let heightColorStops: [Gradient.Stop] = {
        let levels: [CGFloat] = [1.0, 0.86, 0.72, 0.585, 0.45, 0.225, 0.0]
        return levels.map { level in
            Gradient.Stop(color: WinampColors.levelColor(normalized: level), location: 1 - level)
        }
    }()

    var body: some View {
        Canvas { context, size in
            // Classic Winamp graph: faint dark-green dotted grid, with a brighter
            // center line at 0 dB.
            let dotColor = Color(red: 0, green: 0.45, blue: 0.18)
            let rows = 7
            let cols = 19
            for r in 0 ... rows {
                let y = size.height / CGFloat(rows) * CGFloat(r)
                for c in 0 ... cols {
                    let x = size.width / CGFloat(cols) * CGFloat(c)
                    context.fill(
                        Path(CGRect(x: x, y: y, width: 1, height: 1)),
                        with: .color(dotColor)
                    )
                }
            }
            // Brighter horizontal mid-line (0 dB)
            var midline = Path()
            midline.move(to: CGPoint(x: 0, y: size.height / 2))
            midline.addLine(to: CGPoint(x: size.width, y: size.height / 2))
            context.stroke(midline, with: .color(dotColor.opacity(0.9)), lineWidth: 0.5)

            let points = WinampEQBands.responseCurvePoints(
                bandValues: bandValues,
                preampValue: preampValue,
                width: size.width,
                height: size.height
            )
            let curvePath = CatmullRomSpline.path(through: points)

            // Dark under-stroke for depth.
            context.stroke(
                curvePath,
                with: .color(Color.black.opacity(0.6)),
                style: StrokeStyle(lineWidth: lineWidth + 3.0, lineCap: .round, lineJoin: .round)
            )

            // Color the curve by height (green valleys → red peaks) in a single
            // stroke: a vertical gradient evaluates the `levelColor` mapping per
            // pixel-row, replacing the ~80 little segment paths stroked every redraw.
            context.stroke(
                curvePath,
                with: .linearGradient(
                    Gradient(stops: Self.heightColorStops),
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: 0, y: size.height)
                ),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
            )
        }
        .background(Color.black.opacity(0.9))
        .overlay(
            Rectangle()
                .strokeBorder(
                    LinearGradient(
                        colors: [WinampColors.borderDark, Color.black.opacity(0.95)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }
}

// MARK: - Catmull-Rom spline (classic Winamp smooth EQ curve)

enum CatmullRomSpline {
    static func path(through points: [CGPoint]) -> Path {
        var path = Path()
        guard points.count >= 2 else { return path }

        path.move(to: points[0])

        for index in 0 ..< (points.count - 1) {
            let p0 = points[max(0, index - 1)]
            let p1 = points[index]
            let p2 = points[index + 1]
            let p3 = points[min(points.count - 1, index + 2)]

            let control1 = CGPoint(
                x: p1.x + (p2.x - p0.x) / 6,
                y: p1.y + (p2.y - p0.y) / 6
            )
            let control2 = CGPoint(
                x: p2.x - (p3.x - p1.x) / 6,
                y: p2.y - (p3.y - p1.y) / 6
            )
            path.addCurve(to: p2, control1: control1, control2: control2)
        }

        return path
    }
}
