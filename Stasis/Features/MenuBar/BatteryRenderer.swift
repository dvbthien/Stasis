import AppKit
import Foundation
import SwiftUI

@MainActor
struct BatteryRenderer {

    // MARK: - 1. CACHE TRẠNG THÁI GẦN NHẤT
    private static var lastStateKey: String = ""
    private static var lastRenderedImage: NSImage? = nil

    // MARK: - 2. MAIN INTERFACE
    static func render(
        level: Int,
        chargingMode: ChargingMode,
        isLowPower: Bool,
        displayLocation: PercentageDisplayLocation,
        showState: Bool
    ) -> NSImage? {

        // Khởi tạo State Context đóng gói tất cả logic tính toán biến số (Giống SwiftUI Properties)
        let ctx = RenderContext(
            level: level,
            chargingMode: chargingMode,
            isLowPower: isLowPower,
            displayLocation: displayLocation,
            showState: showState
        )

        // Kiểm tra Bộ nhớ đệm (Cache)
        if ctx.stateKey == lastStateKey, let cachedImage = lastRenderedImage {
            return cachedImage
        }

        // Tiến hành dựng Canvas đồ họa dựa trên kích thước tính toán được
        let finalImage = NSImage(size: ctx.targetSize, flipped: false) { rect in

            // Bước A: Vẽ chữ số phần trăm nằm bên ngoài (Chế độ kế bên Icon)
            if ctx.shouldShowOutsidePercentage {
                ctx.outsideText.draw(
                    at: ctx.outsideTextPoint(in: rect),
                    withAttributes: ctx.outsideAttributes
                )
            }

            // Bước B: Vẽ Khung & Núm pin (Outline Layer)
            drawOutlineLayer(in: rect, context: ctx)

            // Bước C: Vẽ Thanh năng lượng (Fill Layer)
            drawFillLayer(in: rect, context: ctx)

            // Bước D: Vẽ Nội dung đè phía trên (Glyph / Chữ số bên trong)
            drawForegroundLayer(in: rect, context: ctx)

            return true
        }

        // Lưu Cache
        lastStateKey = ctx.stateKey
        lastRenderedImage = finalImage

        return finalImage
    }
}

// MARK: - 3. ĐÓNG GÓI BIẾN SỐ & LOGIC TÍNH TOÁN (Tương đương SwiftUI Computed Properties)
extension BatteryRenderer {

    private struct RenderContext {
        let level: Int
        let chargingMode: ChargingMode
        let isLowPower: Bool
        let displayLocation: PercentageDisplayLocation
        let showState: Bool

        // Các trạng thái logic (Booleans)
        var isInsideMode: Bool { displayLocation == .insideIcon }
        var shouldShowOutsidePercentage: Bool { displayLocation == .nextToIcon }
        var isCritical: Bool { showState && level <= 20 }
        var usesPassthroughKnockout: Bool {
            !isCritical && !isLowPower && chargingMode != .charging
        }

        // Cấu hình Kích thước động dựa trên Chế độ hiển thị
        var bodyWidth: CGFloat { isInsideMode ? 28 : 23 }
        var bodyHeight: CGFloat { isInsideMode ? 13 : 11 }
        var capWidth: CGFloat = 2
        var capHeight: CGFloat = 4
        var cornerRadius: CGFloat = 3

        // Chuỗi Văn Bản & Định dạng nghệ thuật
        var outsideText: String { "\(level)%" }
        var outsideAttributes: [NSAttributedString.Key: Any] {
            [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.textColor,
            ]
        }
        var outsideTextSize: NSSize {
            outsideText.size(withAttributes: outsideAttributes)
        }

        // Tính toán Tọa độ X bắt đầu của Thân Pin
        var batteryXOffset: CGFloat {
            let defaultOffset: CGFloat = 2
            if !isInsideMode && shouldShowOutsidePercentage {
                return defaultOffset + outsideTextSize.width + 4  // 4pt khoảng cách (spacing)
            }
            return defaultOffset
        }

        // Tính toán Tổng kích thước vùng vẽ
        var targetSize: NSSize {
            var width = bodyWidth + capWidth + 3
            if shouldShowOutsidePercentage {
                width += outsideTextSize.width + 4
            }
            return NSSize(width: width, height: 22)  // Chiều cao thanh Menu luôn cố định 22pt
        }

        // Bảng Màu Động (Dynamic Color Matching)
        var fillColor: NSColor {
            if isCritical { return .systemRed }
            if isLowPower {
                return NSColor(red: 0.85, green: 0.65, blue: 0.0, alpha: 1.0)
            }
            if chargingMode == .charging { return .systemGreen }
            return .textColor
        }

        // Tạo khóa định danh duy nhất cho bộ nhớ đệm
        var stateKey: String {
            "\(level)_\(chargingMode)_\(isLowPower)_\(displayLocation)_\(showState)_\(NSApp.effectiveAppearance.name)"
        }

        // Hàm phụ trợ tính tọa độ vẽ chữ ngoài
        func outsideTextPoint(in rect: NSRect) -> NSPoint {
            NSPoint(x: 2, y: (rect.height - outsideTextSize.height) / 2)
        }
    }
}

// MARK: - 4. PHÂN TÁCH CÁC HÀM VẼ ĐỒ HỌA (Sub-Rendering Layers)
extension BatteryRenderer {

    /// BƯỚC B: Vẽ Khung và Núm Pin
    private static func drawOutlineLayer(
        in rect: NSRect,
        context: RenderContext
    ) {
        let bodyRect = NSRect(
            x: context.batteryXOffset,
            y: (rect.height - context.bodyHeight) / 2,
            width: context.bodyWidth,
            height: context.bodyHeight
        )

        // 1. Vẽ thân pin
        if context.isInsideMode {
            NSColor.labelColor.withAlphaComponent(0.3).setFill()
            NSBezierPath(
                roundedRect: bodyRect,
                xRadius: context.cornerRadius,
                yRadius: context.cornerRadius
            ).fill()
        } else {
            NSColor.textColor.withAlphaComponent(0.4).setStroke()
            let path = NSBezierPath(
                roundedRect: bodyRect,
                xRadius: context.cornerRadius,
                yRadius: context.cornerRadius
            )
            path.lineWidth = 1
            path.stroke()
        }

        // 2. Vẽ núm pin (Cap)
        let capRect = NSRect(
            x: bodyRect.maxX + 1,
            y: (rect.height - context.capHeight) / 2,
            width: context.capWidth,
            height: context.capHeight
        )
        let capColor = NSColor.textColor.withAlphaComponent(0.4)
        capColor.setFill()
        NSBezierPath(roundedRect: capRect, xRadius: 1.5, yRadius: 1.5).fill()
    }

    /// BƯỚC C: Vẽ Thanh Dung Lượng Pin Chạy Theo Phần Trăm
    private static func drawFillLayer(in rect: NSRect, context: RenderContext) {
        let bodyRect = NSRect(
            x: context.batteryXOffset,
            y: (rect.height - context.bodyHeight) / 2,
            width: context.bodyWidth,
            height: context.bodyHeight
        )

        if context.isInsideMode {
            let fillWidth = max(
                0,
                context.bodyWidth * CGFloat(context.level) / 100
            )
            if fillWidth > 0 {
                NSGraphicsContext.current?.saveGraphicsState()
                // Giới hạn vùng vẽ (Clip) không tràn qua bo góc thân pin
                NSBezierPath(
                    roundedRect: bodyRect,
                    xRadius: context.cornerRadius,
                    yRadius: context.cornerRadius
                ).addClip()
                fillRect(
                    NSRect(
                        x: context.batteryXOffset,
                        y: bodyRect.minY,
                        width: fillWidth,
                        height: context.bodyHeight
                    ),
                    with: context.fillColor
                )
                NSGraphicsContext.current?.restoreGraphicsState()
            }
        } else {
            let fillWidth = max(
                0,
                (context.bodyWidth - 3) * CGFloat(context.level) / 100
            )
            if fillWidth > 0 {
                // Thụt lề nội đô 1.5pt để nằm cân đối trong khung vẽ border ngoài
                fillRect(
                    NSRect(
                        x: context.batteryXOffset + 1.5,
                        y: bodyRect.minY + 1.5,
                        width: fillWidth,
                        height: context.bodyHeight - 3
                    ),
                    with: context.fillColor
                )
            }
        }
    }
    
    private static let batteryTextAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 8.5, weight: .bold),
        .foregroundColor: NSColor.textColor,
    ]
    private static let glyphAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 12, weight: .heavy),
        .foregroundColor: NSColor.textColor,
        .strokeColor: NSColor.controlBackgroundColor,
        .strokeWidth: -5.0,
    ]

    /// BƯỚC D: Vẽ Chữ Số Đè Bên Trong Hoặc Ký Hiệu Sạc (Bolt/Plug)
    private static func drawForegroundLayer(
        in rect: NSRect,
        context: RenderContext
    ) {
        let isDischarging = context.chargingMode == .discharging
        let glyph = context.chargingMode == .charging ? "􀋦" : "􂬺"
        if context.isInsideMode {
            let batteryText =
                isDischarging ? "\(context.level)" : "\(context.level)\(glyph)"

            let batteryTextSize = batteryText.size(withAttributes: batteryTextAttributes)

            let batteryTextX =
                context.batteryXOffset + (context.bodyWidth - batteryTextSize.width)
                / 2
            let batteryTextY = (rect.height - batteryTextSize.height) / 2 + 0.5
            
            // Kỹ thuật đục lỗ (Knockout) — chỉ save/restore khi thực sự cần đổi blend mode
            if context.usesPassthroughKnockout {
                NSGraphicsContext.current?.saveGraphicsState()
                NSGraphicsContext.current?.cgContext.setBlendMode(
                    .destinationOut
                )

                batteryText.draw(
                    at: NSPoint(x: batteryTextX, y: batteryTextY),
                    withAttributes: batteryTextAttributes
                )

                NSGraphicsContext.current?.restoreGraphicsState()
            } else {
                batteryText.draw(
                    at: NSPoint(x: batteryTextX, y: batteryTextY),
                    withAttributes: batteryTextAttributes
                )
            }

        } else if !isDischarging {
            let glyphSize = glyph.size(withAttributes: glyphAttributes)
            let glyphX =
                context.batteryXOffset + (context.bodyWidth - glyphSize.width)
                / 2
            let glyphY = (rect.height - glyphSize.height) / 2 + 0.5

            // Vẽ đúng 1 dòng duy nhất là xong, hệ thống tự lo phần viền mịn
            glyph.draw(
                at: NSPoint(x: glyphX, y: glyphY),
                withAttributes: glyphAttributes
            )
        }
    }

    private static func fillRect(_ rect: NSRect, with color: NSColor) {
        color.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 1.5, yRadius: 1.5).fill()
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 16) {
        // --- NHÓM 1: HIỂN THỊ TIÊU CHUẨN (KHÔNG CHỮ) ---
        Group {
            Text("Màu sắc theo trạng thái (Ẩn phần trăm)")
                .font(.headline).foregroundStyle(.secondary)

            HStack(spacing: 20) {
                if let normal = BatteryRenderer.render(
                    level: 75,
                    chargingMode: .discharging,
                    isLowPower: false,
                    displayLocation: .hidden,
                    showState: true
                ) {
                    VStack {
                        Image(nsImage: normal)
                        Text("Bình thường").font(.caption)
                    }
                }
                if let lowPower = BatteryRenderer.render(
                    level: 50,
                    chargingMode: .discharging,
                    isLowPower: true,
                    displayLocation: .hidden,
                    showState: true
                ) {
                    VStack {
                        Image(nsImage: lowPower)
                        Text("Tiết kiệm pin (Vàng)").font(.caption)
                    }
                }
                if let charging = BatteryRenderer.render(
                    level: 80,
                    chargingMode: .charging,
                    isLowPower: false,
                    displayLocation: .hidden,
                    showState: true
                ) {
                    VStack {
                        Image(nsImage: charging)
                        Text("Đang sạc (Xanh)").font(.caption)
                    }
                }
                if let charging = BatteryRenderer.render(
                    level: 80,
                    chargingMode: .pluggedIn,
                    isLowPower: false,
                    displayLocation: .hidden,
                    showState: true
                ) {
                    VStack {
                        Image(nsImage: charging)
                        Text("Dùng nguồn").font(.caption)
                    }
                }
                if let critical = BatteryRenderer.render(
                    level: 15,
                    chargingMode: .discharging,
                    isLowPower: false,
                    displayLocation: .hidden,
                    showState: true
                ) {
                    VStack {
                        Image(nsImage: critical)
                        Text("Pin yếu (Đỏ)").font(.caption)
                    }
                }
            }
        }

        Divider()

        // --- NHÓM 2: CHỮ BÊN TRONG VIÊN PIN (KNOCKOUT) ---
        Group {
            Text("Chữ đục lỗ bên trong (.insideIcon)")
                .font(.headline).foregroundStyle(.secondary)

            HStack(spacing: 20) {
                ForEach([100, 75, 60, 60, 61, 40, 25, 15], id: \.self) {
                    level in
                    if let insideImg = BatteryRenderer.render(
                        level: level,
                        chargingMode: .discharging,
                        isLowPower: (level == 75),
                        displayLocation: .insideIcon,
                        showState: true
                    ) {
                        VStack {
                            Image(nsImage: insideImg)
                            Text("\(level)%").font(.caption)
                        }
                    }
                }
            }
        }

        Divider()

        // --- NHÓM 3: CHỮ BÊN CẠNH VIÊN PIN ---
        Group {
            Text("Chữ nằm bên cạnh (.nextToIcon)")
                .font(.headline).foregroundStyle(.secondary)

            HStack(spacing: 20) {
                if let nextToImg = BatteryRenderer.render(
                    level: 100,
                    chargingMode: .discharging,
                    isLowPower: false,
                    displayLocation: .nextToIcon,
                    showState: true
                ) {
                    Image(nsImage: nextToImg)
                }
                if let nextToImg2 = BatteryRenderer.render(
                    level: 45,
                    chargingMode: .discharging,
                    isLowPower: true,
                    displayLocation: .nextToIcon,
                    showState: true
                ) {
                    Image(nsImage: nextToImg2)
                }
            }
        }
    }
    .padding()
    // Giả lập màu nền giống Menu Bar của macOS để dễ quan sát nét vẽ
    .background(Color(NSColor.windowBackgroundColor))
    // Bạn có thể đổi .dark thành .light tại đây để test khả năng tự đổi màu viền của Renderer
    .preferredColorScheme(.dark)
}
