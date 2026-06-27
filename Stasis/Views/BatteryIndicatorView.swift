import SwiftUI

struct BatteryIndicatorView: View {
    let batteryLevel: Int
    let chargingMode: ChargingMode
    var isLowPowerModeEnabled: Bool = false
    var percentageDisplayLocation: PercentageDisplayLocation = .hidden
    var showState: Bool = false

    @State private var insidePercentageFrame: CGRect?

    private var batteryText: String { String(batteryLevel) }

    private var digitCount: CGFloat {
        switch batteryLevel {
            case 100...: return 3
            case 10...99: return 2
            default: return 1
        }
    }

    private var shouldShowInsidePercentage: Bool {
        percentageDisplayLocation == .insideIcon
    }

    private var shouldShowOutsidePercentage: Bool {
        percentageDisplayLocation == .nextToIcon
    }

    private var isCritical: Bool {
        showState && batteryLevel <= 20
    }

    private var fillColor: Color {
        if isCritical { return .red }
        if isLowPowerModeEnabled { return .yellow }
        if chargingMode == .charging { return .green }
        return .primary
    }

    private var foregroundColor: Color {
        isLowPowerModeEnabled ? .black : .white
    }

    private var usesPassthrough: Bool {
        !isCritical && !isLowPowerModeEnabled && chargingMode != .charging
    }

    private enum Layout {
        static let batteryHeight: CGFloat = 11
        static let batteryWidth: CGFloat = 23
        static let insideBatteryHeight: CGFloat = 14
        static let insideBatteryWidth: CGFloat = 28
        static let terminalWidth: CGFloat = 1.3
        static let terminalHeight: CGFloat = 3.6
        static let insideTerminalWidth: CGFloat = 2
        static let insideTerminalHeight: CGFloat = 4
        static let cornerRadius: CGFloat = 3
        static let insideCornerRadius: CGFloat = 3.5
        static let strokeWidth: CGFloat = 1
        static let fillInset: CGFloat = 1.5
        static let outlineOpacity: CGFloat = 0.4
        static let glyphEdgeHint: CGFloat = 3
        static let knockoutCoordinateSpace = "knockoutBody"
        static let insideTrackColor = Color(nsColor: .tertiaryLabelColor)
        static let levelAnimation: Animation = .easeInOut(duration: 0.25)
    }

    var body: some View {
        HStack(spacing: 4) {
            if shouldShowOutsidePercentage {
                Text("\(batteryLevel)%")
                    .font(.system(size: 11))
                    .monospacedDigit()
            }

            HStack(spacing: 0) {
                batteryBody
                if shouldShowInsidePercentage {
                    BatteryTerminal(
                        width: Layout.insideTerminalWidth,
                        height: Layout.insideTerminalHeight,
                        cornerRadius: 1
                    )
                } else {
                    BatteryTerminal(
                        width: Layout.terminalWidth,
                        height: Layout.terminalHeight,
                        cornerRadius: 1
                    )
                }
            }
        }
        .foregroundStyle(.primary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        var parts = ["Battery \(batteryLevel) percent"]
        switch chargingMode {
        case .charging: parts.append("charging")
        case .pluggedIn: parts.append("plugged in")
        case .discharging: break
        }
        if isLowPowerModeEnabled { parts.append("low power mode") }
        return parts.joined(separator: ", ")
    }

    @ViewBuilder
    private var batteryBody: some View {
        if shouldShowInsidePercentage {
            knockoutBatteryBody
                .frame(width: Layout.insideBatteryWidth, height: Layout.insideBatteryHeight)
        } else {
            overlayBatteryBody
                .frame(width: Layout.batteryWidth, height: Layout.batteryHeight)
        }
    }

    private var knockoutBatteryBody: some View {
        ZStack {
            Rectangle()
                .fill(Layout.insideTrackColor)

            Rectangle()
                .fill(fillColor)
                .frame(width: fillWidth(usableWidth: Layout.insideBatteryWidth))
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(Layout.levelAnimation, value: batteryLevel)


            insideContent
        }
        .coordinateSpace(name: Layout.knockoutCoordinateSpace)
        .onPreferenceChange(InsidePercentageFramePreferenceKey.self) {
            insidePercentageFrame = $0
        }
        .compositingGroup()
        .clipShape(RoundedRectangle(cornerRadius: Layout.insideCornerRadius))
    }

    private func fillWidth(usableWidth: CGFloat) -> CGFloat {
        let raw = max(0, usableWidth * CGFloat(batteryLevel) / 100)
        guard usesPassthrough, let textFrame = insidePercentageFrame else {
            return raw
        }
        let digitWidth = textFrame.width / digitCount
        let leftEdge = textFrame.minX
        let rawIndex = ((raw - leftEdge) / digitWidth).rounded()
        let index = min(max(rawIndex, 0), digitCount)
        let snapped = min(max(leftEdge + index * digitWidth, 0), usableWidth)
        return abs(snapped - raw) < Layout.glyphEdgeHint ? snapped : raw
    }

    private var insideContent: some View {
        HStack(spacing: 1.5) {
            Text(verbatim: batteryText)
                .font(.system(size: 10, weight: .heavy))
                .monospacedDigit()
                .background {
                    GeometryReader { textGeo in
                        Color.clear.preference(
                            key: InsidePercentageFramePreferenceKey.self,
                            value: textGeo.frame(
                                in: .named(Layout.knockoutCoordinateSpace)
                            )
                        )
                    }
                }
            chargingGlyph
                .font(.system(size: 8, weight: .black))
        }
        .lineLimit(1)
        .foregroundStyle(foregroundColor)
        .blendMode(usesPassthrough ? .destinationOut : .normal)
    }

    @ViewBuilder
    private var chargingGlyph: some View {
        if chargingMode == .charging {
            Image(systemName: "bolt.fill")
        } else if chargingMode == .pluggedIn {
            Image(systemName: "powerplug.portrait.fill")
             
        }
    }

    private var overlayBatteryBody: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Layout.cornerRadius)
                .stroke(lineWidth: Layout.strokeWidth)
                .opacity(Layout.outlineOpacity)

               let fillWidth =
                    (Layout.batteryWidth - Layout.fillInset * 2)
                    * CGFloat(batteryLevel)
                    / 100
                RoundedRectangle(
                    cornerRadius: Layout.cornerRadius - Layout.fillInset
                )
                .fill(fillColor)
                .frame(width: max(0, fillWidth))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Layout.fillInset)
                .animation(Layout.levelAnimation, value: batteryLevel)

        }
        .overlay {
            if chargingMode == .charging {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(.primary)
                    .shadow(color: .black.opacity(0.6), radius: 0.5)
            } else if chargingMode == .pluggedIn {
                Image(systemName: "powerplug.portrait.fill")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(.primary)
                    .shadow(color: .black.opacity(0.6), radius: 0.5)
            }
        }
    }
}

private struct InsidePercentageFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect?
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = nextValue() ?? value
    }
}

struct BatteryTerminal: View, Equatable {
    let width: CGFloat
    let height: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: cornerRadius,
            topTrailingRadius: cornerRadius
        )
        .fill(.primary)
        .frame(width: width, height: height)
        .opacity(0.4)
        .offset(x: 1)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 16) {
        ForEach([100, 80, 50, 20, 10, 5], id: \.self) { level in
            HStack(spacing: 20) {
                BatteryIndicatorView(batteryLevel: level, chargingMode: .discharging)
                BatteryIndicatorView(batteryLevel: level, chargingMode: .charging)
                BatteryIndicatorView(batteryLevel: level, chargingMode: .pluggedIn)
            }
        }

        Divider()
        Text("Inside Icon — normal / charging / plugged")
            .font(.caption).foregroundStyle(.secondary)

        ForEach([100, 80, 50, 20, 10, 5], id: \.self) { level in
            HStack(spacing: 20) {
                BatteryIndicatorView(
                    batteryLevel: level, chargingMode: .discharging,
                    percentageDisplayLocation: .insideIcon, showState: true)
                BatteryIndicatorView(
                    batteryLevel: level, chargingMode: .charging,
                    percentageDisplayLocation: .insideIcon, showState: true)
                BatteryIndicatorView(
                    batteryLevel: level, chargingMode: .pluggedIn,
                    percentageDisplayLocation: .insideIcon, showState: true)
            }
        }

        Divider()
        Text("Inside Icon — Low Power Mode (critical red takes priority)")
            .font(.caption).foregroundStyle(.secondary)

        ForEach([100, 50, 10, 5], id: \.self) { level in
            HStack(spacing: 20) {
                BatteryIndicatorView(
                    batteryLevel: level, chargingMode: .discharging,
                    isLowPowerModeEnabled: true,
                    percentageDisplayLocation: .insideIcon, showState: true)
                BatteryIndicatorView(
                    batteryLevel: level, chargingMode: .charging,
                    isLowPowerModeEnabled: true,
                    percentageDisplayLocation: .insideIcon, showState: true)
            }
        }
    }
    .padding()
    .background(Color(NSColor.windowBackgroundColor))
}
