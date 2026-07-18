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

      // Bố cục dùng chung tính MỘT lần để cả 3 layer luôn khớp nhau
      let bodyRect = ctx.bodyRect(in: rect)
      let plan = ctx.isInsideMode
        ? insidePlan(in: bodyRect, context: ctx)
        : nil

      // Bước B: Vẽ Khung & Núm pin (Outline Layer)
      drawOutlineLayer(in: rect, bodyRect: bodyRect, plan: plan, context: ctx)

      // Bước C: Vẽ Thanh năng lượng (Fill Layer)
      drawFillLayer(bodyRect: bodyRect, plan: plan, context: ctx)

      // Bước D: Vẽ Nội dung đè phía trên (Glyph / Chữ số bên trong)
      drawForegroundLayer(in: rect, plan: plan, context: ctx)

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

  /// Các thông số hình học và kiểu vẽ tập trung tại một nơi để dễ tinh chỉnh.
  private enum Layout {
    static let canvasHeight: CGFloat = 24

    static let insideBodyWidth: CGFloat = 28
    static let insideBodyHeight: CGFloat = 13
    static let outsideBodyWidth: CGFloat = 23
    static let outsideBodyHeight: CGFloat = 11
    static let insideCornerRadius: CGFloat = 4
    static let outsideCornerRadius: CGFloat = 3

    static let batteryLeadingInset: CGFloat = 2
    static let capSpacing: CGFloat = 1
    static let capWidth: CGFloat = 2
    static let capHeight: CGFloat = 4
    static let capCornerRadius: CGFloat = 1.5

    static let outsideTextSpacing: CGFloat = 4
    static let outsideTextSize: CGFloat = 11
    static let insideTextSize: CGFloat = 8.5
    static let textWeight: NSFont.Weight = .bold

    static let insideSymbolSize: CGFloat = 7
    static let outsideSymbolSize: CGFloat = 10
    static let symbolSpacing: CGFloat = 0.75
    static let symbolWeight: NSFont.Weight = .bold

    static let insideTrackOpacity: CGFloat = 0.3
    static let outsideOutlineOpacity: CGFloat = 0.4
    static let outsideOutlineWidth: CGFloat = 1
    static let outsideFillInset: CGFloat = 1.5
    static let outsideFillCornerRadius: CGFloat = 1.5

    static let glyphAntialiasPadding: CGFloat = 0.5
    static let fallbackDisplayScale: CGFloat = 2
    static let symbolHaloRadius: CGFloat = 0.75

    static let fullBatteryLevel: CGFloat = 100
    static let criticalBatteryLevel = 20
    static let chargingSymbolName = "bolt.fill"
    static let pluggedInSymbolName = "powerplug.portrait.fill"

    static let foregroundColor = NSColor.textColor
    static let insideTrackColor = NSColor.labelColor
    static let criticalFillColor = NSColor.systemRed
    static let chargingFillColor = NSColor.systemGreen
    static let lowPowerFillColor = NSColor(
      red: 0.85,
      green: 0.65,
      blue: 0,
      alpha: 1
    )
  }

  private struct RenderContext {
    let level: Int
    let chargingMode: ChargingMode
    let isLowPower: Bool
    let displayLocation: PercentageDisplayLocation
    let showState: Bool

    // Các trạng thái logic (Booleans)
    var isInsideMode: Bool { displayLocation == .insideIcon }
    var shouldShowOutsidePercentage: Bool { displayLocation == .nextToIcon }
    var isCritical: Bool {
      showState && level <= Layout.criticalBatteryLevel
    }
    var usesPassthroughKnockout: Bool {
      !isCritical && !isLowPower && chargingMode != .charging
    }

    // Cấu hình Kích thước động dựa trên Chế độ hiển thị
    var bodyWidth: CGFloat {
      isInsideMode ? Layout.insideBodyWidth : Layout.outsideBodyWidth
    }
    var bodyHeight: CGFloat {
      isInsideMode ? Layout.insideBodyHeight : Layout.outsideBodyHeight
    }
    var cornerRadius: CGFloat {
      isInsideMode ? Layout.insideCornerRadius : Layout.outsideCornerRadius
    }

    // Chuỗi Văn Bản & Định dạng nghệ thuật
    var outsideText: String { "\(level)%" }
    var outsideAttributes: [NSAttributedString.Key: Any] {
      [
        .font: NSFont.systemFont(ofSize: Layout.outsideTextSize),
        .foregroundColor: Layout.foregroundColor,
      ]
    }
    var outsideTextSize: NSSize {
      outsideText.size(withAttributes: outsideAttributes)
    }

    // Tính toán Tọa độ X bắt đầu của Thân Pin
    var batteryXOffset: CGFloat {
      if !isInsideMode && shouldShowOutsidePercentage {
        return Layout.batteryLeadingInset + outsideTextSize.width
          + Layout.outsideTextSpacing
      }
      return Layout.batteryLeadingInset
    }

    // Tính toán Tổng kích thước vùng vẽ
    var targetSize: NSSize {
      var width = bodyWidth + Layout.batteryLeadingInset
        + Layout.capSpacing + Layout.capWidth
      if shouldShowOutsidePercentage {
        width += outsideTextSize.width + Layout.outsideTextSpacing
      }
      return NSSize(width: width, height: Layout.canvasHeight)
    }

    // Bảng Màu Động (Dynamic Color Matching)
    var fillColor: NSColor {
      if isCritical { return Layout.criticalFillColor }
      if isLowPower { return Layout.lowPowerFillColor }
      if chargingMode == .charging { return Layout.chargingFillColor }
      return Layout.foregroundColor
    }

    // Tạo khóa định danh duy nhất cho bộ nhớ đệm
    var stateKey: String {
      "\(level)_\(chargingMode)_\(isLowPower)_\(displayLocation)_\(showState)_\(NSApp.effectiveAppearance.name)"
    }

    // Hàm phụ trợ tính tọa độ vẽ chữ ngoài
    func outsideTextPoint(in rect: NSRect) -> NSPoint {
      NSPoint(
        x: Layout.batteryLeadingInset,
        y: (rect.height - outsideTextSize.height) / 2
      )
    }

    // Khung thân pin căn giữa theo chiều dọc vùng vẽ
    func bodyRect(in rect: NSRect) -> NSRect {
      NSRect(
        x: batteryXOffset,
        y: (rect.height - bodyHeight) / 2,
        width: bodyWidth,
        height: bodyHeight
      )
    }
  }
}

// MARK: - 4. PHÂN TÁCH CÁC HÀM VẼ ĐỒ HỌA (Sub-Rendering Layers)
extension BatteryRenderer {

  /// BƯỚC B: Vẽ Khung và Núm Pin
  private static func drawOutlineLayer(
    in rect: NSRect,
    bodyRect: NSRect,
    plan: InsidePlan?,
    context: RenderContext
  ) {
    // 1. Vẽ thân pin
    if let plan {
      // Nền mờ chỉ vẽ ở phần chưa có năng lượng — fill trực tiếp path bo góc
      // (không dùng blend mode .copy) để mép cong được antialias mượt
      if plan.fillWidth < bodyRect.width {
        NSGraphicsContext.current?.saveGraphicsState()
        NSBezierPath(
          rect: NSRect(
            x: bodyRect.minX + plan.fillWidth,
            y: bodyRect.minY,
            width: bodyRect.width - plan.fillWidth,
            height: bodyRect.height
          )
        ).addClip()
        Layout.insideTrackColor.withAlphaComponent(
          Layout.insideTrackOpacity
        ).setFill()
        insideBodyPath(bodyRect, context: context).fill()
        NSGraphicsContext.current?.restoreGraphicsState()
      }
    } else {
      Layout.foregroundColor.withAlphaComponent(
        Layout.outsideOutlineOpacity
      ).setStroke()
      let path = NSBezierPath(
        roundedRect: bodyRect,
        xRadius: context.cornerRadius,
        yRadius: context.cornerRadius
      )
      path.lineWidth = Layout.outsideOutlineWidth
      path.stroke()
    }

    // 2. Vẽ núm pin (Cap)
    let capRect = NSRect(
      x: bodyRect.maxX + Layout.capSpacing,
      y: (rect.height - Layout.capHeight) / 2,
      width: Layout.capWidth,
      height: Layout.capHeight
    )
    let capColor = Layout.foregroundColor.withAlphaComponent(
      Layout.outsideOutlineOpacity
    )
    capColor.setFill()
    NSBezierPath(
      roundedRect: capRect,
      xRadius: Layout.capCornerRadius,
      yRadius: Layout.capCornerRadius
    ).fill()
  }

  /// BƯỚC C: Vẽ Thanh Dung Lượng Pin Chạy Theo Phần Trăm
  private static func drawFillLayer(
    bodyRect: NSRect,
    plan: InsidePlan?,
    context: RenderContext
  ) {
    if let plan {
      if plan.fillWidth > 0 {
        NSGraphicsContext.current?.saveGraphicsState()
        // Chỉ clip bằng hình chữ nhật thẳng trục (mép đứng không cần antialias);
        // góc cong đến từ chính path bo góc được fill nên luôn mượt
        if plan.fillWidth < bodyRect.width {
          NSBezierPath(
            rect: NSRect(
              x: bodyRect.minX,
              y: bodyRect.minY,
              width: plan.fillWidth,
              height: bodyRect.height
            )
          ).addClip()
        }
        context.fillColor.setFill()
        insideBodyPath(bodyRect, context: context).fill()
        NSGraphicsContext.current?.restoreGraphicsState()
      }
    } else {
      let fillWidth = max(
        0,
        (context.bodyWidth - Layout.outsideFillInset * 2)
          * CGFloat(context.level) / Layout.fullBatteryLevel
      )
      if fillWidth > 0 {
        // Thụt đều theo cấu hình để fill nằm cân đối trong khung ngoài.
        fillRect(
          NSRect(
            x: context.batteryXOffset + Layout.outsideFillInset,
            y: bodyRect.minY + Layout.outsideFillInset,
            width: fillWidth,
            height: context.bodyHeight - Layout.outsideFillInset * 2
          ),
          with: context.fillColor
        )
      }
    }
  }

  private static let batteryTextAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(
      ofSize: Layout.insideTextSize,
      weight: Layout.textWeight
    ),
    .foregroundColor: Layout.foregroundColor,
  ]

  /// Vùng chiếm chỗ theo trục X của một glyph (đã đệm antialias):
  /// mép fill rơi vào `range` sẽ được snap ra `leadingEdgeX` / `trailingEdgeX`.
  private struct GlyphZone {
    let range: ClosedRange<CGFloat>
    let leadingEdgeX: CGFloat
    let trailingEdgeX: CGFloat
  }

  private struct InsideForegroundLayout {
    let percentageText: String
    let percentagePoint: NSPoint
    let symbolImage: NSImage?
    let symbolRect: NSRect?
    /// Các vùng cấm đã gộp chồng lấn, theo thứ tự trái sang phải
    let glyphZones: [GlyphZone]
  }

  /// Bố cục inside dùng chung cho cả 3 layer — tính MỘT lần mỗi lần render
  /// để mép nền, mép fill và vị trí chữ không bao giờ lệch nhau.
  private struct InsidePlan {
    let fillWidth: CGFloat
    let layout: InsideForegroundLayout
  }

  private static func insidePlan(
    in bodyRect: NSRect,
    context: RenderContext
  ) -> InsidePlan {
    let layout = insideForegroundLayout(in: bodyRect, context: context)
    return InsidePlan(
      fillWidth: insideFillWidth(
        in: bodyRect,
        layout: layout,
        context: context
      ),
      layout: layout
    )
  }

  private static func stateSymbol(
    for chargingMode: ChargingMode,
    pointSize: CGFloat
  ) -> NSImage? {
    let symbolName: String
    switch chargingMode {
    case .charging:
      symbolName = Layout.chargingSymbolName
    case .pluggedIn:
      symbolName = Layout.pluggedInSymbolName
    case .discharging:
      return nil
    }

    guard let symbol = NSImage(
      systemSymbolName: symbolName,
      accessibilityDescription: nil
    ) else {
      return nil
    }

    let sizeConfiguration = NSImage.SymbolConfiguration(
      pointSize: pointSize,
      weight: Layout.symbolWeight
    )
    let colorConfiguration = NSImage.SymbolConfiguration(
      hierarchicalColor: Layout.foregroundColor
    )
    return symbol.withSymbolConfiguration(
      sizeConfiguration.applying(colorConfiguration)
    )
  }

  private static func insideForegroundLayout(
    in bodyRect: NSRect,
    context: RenderContext
  ) -> InsideForegroundLayout {
    let percentageText = "\(context.level)"
    let percentageSize = percentageText.size(
      withAttributes: batteryTextAttributes
    )
    let percentageInkBounds = percentageText.boundingRect(
      with: NSSize(
        width: CGFloat.greatestFiniteMagnitude,
        height: CGFloat.greatestFiniteMagnitude
      ),
      options: [.usesDeviceMetrics],
      attributes: batteryTextAttributes
    )
    let symbolImage = stateSymbol(
      for: context.chargingMode,
      pointSize: Layout.insideSymbolSize
    )
    let symbolSpacing = symbolImage == nil ? 0 : Layout.symbolSpacing
    let symbolSize = symbolImage?.size ?? .zero
    let contentWidth =
      percentageInkBounds.width + symbolSpacing + symbolSize.width
    let contentMinX = bodyRect.midX - contentWidth / 2
    let percentagePoint = NSPoint(
      x: contentMinX - percentageInkBounds.minX,
      y: bodyRect.midY - percentageSize.height / 2
    )
    let symbolRect = symbolImage.map { _ in
      NSRect(
        x: contentMinX + percentageInkBounds.width + symbolSpacing,
        y: bodyRect.midY - symbolSize.height / 2,
        width: symbolSize.width,
        height: symbolSize.height
      )
    }

    // Đo vùng cấm của từng glyph (chữ số + ký hiệu trạng thái)
    var zones: [GlyphZone] = []
    var characterOriginX = percentagePoint.x
    for character in percentageText {
      let characterText = String(character)
      let characterAdvance = characterText.size(
        withAttributes: batteryTextAttributes
      ).width
      let characterInkBounds = characterText.boundingRect(
        with: NSSize(
          width: CGFloat.greatestFiniteMagnitude,
          height: CGFloat.greatestFiniteMagnitude
        ),
        options: [.usesDeviceMetrics],
        attributes: batteryTextAttributes
      )
      let paddedMinX =
        characterOriginX + characterInkBounds.minX
        - Layout.glyphAntialiasPadding
      let paddedMaxX =
        characterOriginX + characterInkBounds.maxX
        + Layout.glyphAntialiasPadding
      zones.append(
        GlyphZone(
          range: paddedMinX...paddedMaxX,
          leadingEdgeX: min(characterOriginX, paddedMinX),
          trailingEdgeX: max(characterOriginX + characterAdvance, paddedMaxX)
        )
      )
      characterOriginX += characterAdvance
    }
    if let symbolRect {
      let paddedMinX = symbolRect.minX - Layout.glyphAntialiasPadding
      let paddedMaxX = symbolRect.maxX + Layout.glyphAntialiasPadding
      zones.append(
        GlyphZone(
          range: paddedMinX...paddedMaxX,
          leadingEdgeX: paddedMinX,
          trailingEdgeX: paddedMaxX
        )
      )
    }

    return InsideForegroundLayout(
      percentageText: percentageText,
      percentagePoint: percentagePoint,
      symbolImage: symbolImage,
      symbolRect: symbolRect,
      glyphZones: mergedGlyphZones(zones)
    )
  }

  /// Gộp các vùng cấm chồng lấn (kể cả phần đệm antialias của glyph kế bên)
  /// để mép sau khi snap không bao giờ rơi vào một vùng cấm khác.
  private static func mergedGlyphZones(_ zones: [GlyphZone]) -> [GlyphZone] {
    var merged: [GlyphZone] = []
    for zone in zones.sorted(by: { $0.range.lowerBound < $1.range.lowerBound })
    {
      guard let last = merged.last,
        zone.range.lowerBound <= last.range.upperBound
      else {
        merged.append(zone)
        continue
      }
      merged[merged.count - 1] = GlyphZone(
        range: last.range.lowerBound...max(
          last.range.upperBound,
          zone.range.upperBound
        ),
        leadingEdgeX: min(last.leadingEdgeX, zone.leadingEdgeX),
        trailingEdgeX: max(last.trailingEdgeX, zone.trailingEdgeX)
      )
    }
    return merged
  }

  private static func insideBodyPath(
    _ bodyRect: NSRect,
    context: RenderContext
  ) -> NSBezierPath {
    NSBezierPath(
      roundedRect: bodyRect,
      xRadius: context.cornerRadius,
      yRadius: context.cornerRadius
    )
  }

  /// Chiều rộng thanh năng lượng, đã snap tránh glyph và căn theo pixel vật lý
  /// để mép ranh giới giữa fill và nền luôn sắc nét.
  private static func insideFillWidth(
    in bodyRect: NSRect,
    layout: InsideForegroundLayout,
    context: RenderContext
  ) -> CGFloat {
    let rawFillWidth = max(
      0,
      context.bodyWidth * CGFloat(context.level) / Layout.fullBatteryLevel
    )
    let snappedWidth = snappedInsideFillWidth(
      rawFillWidth,
      in: bodyRect,
      layout: layout,
      context: context
    )
    let scale = NSGraphicsContext.current
      .map { abs($0.cgContext.ctm.a) } ?? Layout.fallbackDisplayScale
    guard scale > 0 else { return snappedWidth }
    return (snappedWidth * scale).rounded() / scale
  }

  /// Giữ mép fill không cắt ngang glyph nào: nếu rơi vào vùng cấm thì snap về
  /// mép GẦN HƠN của vùng đó, để sai số mức pin hiển thị là nhỏ nhất.
  private static func snappedInsideFillWidth(
    _ rawFillWidth: CGFloat,
    in bodyRect: NSRect,
    layout: InsideForegroundLayout,
    context: RenderContext
  ) -> CGFloat {
    guard context.usesPassthroughKnockout else { return rawFillWidth }

    let rawEdgeX = bodyRect.minX + rawFillWidth
    guard
      let zone = layout.glyphZones.first(where: {
        $0.range.contains(rawEdgeX)
      })
    else { return rawFillWidth }

    let snappedEdgeX =
      rawEdgeX - zone.leadingEdgeX <= zone.trailingEdgeX - rawEdgeX
      ? zone.leadingEdgeX
      : zone.trailingEdgeX
    return min(max(snappedEdgeX - bodyRect.minX, 0), bodyRect.width)
  }

  /// BƯỚC D: Vẽ Chữ Số Đè Bên Trong Hoặc Ký Hiệu Sạc (Bolt/Plug)
  private static func drawForegroundLayer(
    in rect: NSRect,
    plan: InsidePlan?,
    context: RenderContext
  ) {
    let isDischarging = context.chargingMode == .discharging
    if let plan {
      let layout = plan.layout

      // Kỹ thuật đục lỗ (Knockout) — chỉ save/restore khi thực sự cần đổi blend mode
      if context.usesPassthroughKnockout {
        NSGraphicsContext.current?.saveGraphicsState()
        NSGraphicsContext.current?.cgContext.setBlendMode(
          .destinationOut
        )

        drawInsideForeground(
          layout,
          symbolOperation: .destinationOut
        )

        NSGraphicsContext.current?.restoreGraphicsState()
      } else {
        drawInsideForeground(layout, symbolOperation: .sourceOver)
      }

    } else if !isDischarging {
      guard let symbol = stateSymbol(
        for: context.chargingMode,
        pointSize: Layout.outsideSymbolSize
      ) else { return }
      let symbolRect = NSRect(
        x: context.batteryXOffset
          + (context.bodyWidth - symbol.size.width) / 2,
        y: rect.midY - symbol.size.height / 2,
        width: symbol.size.width,
        height: symbol.size.height
      )
      drawSymbolWithKnockoutHalo(symbol, in: symbolRect)
    }
  }

  /// Recreates the contrast halo previously provided by the stroked text
  /// glyph. The expanded destination-out mask separates a system symbol from
  /// both the fill and outline before the symbol is drawn normally on top.
  private static func drawSymbolWithKnockoutHalo(
    _ symbol: NSImage,
    in rect: NSRect
  ) {
    let radius = Layout.symbolHaloRadius
    let diagonalOffset = radius / sqrt(2)
    let offsets = [
      NSPoint(x: -radius, y: 0),
      NSPoint(x: radius, y: 0),
      NSPoint(x: 0, y: -radius),
      NSPoint(x: 0, y: radius),
      NSPoint(x: -diagonalOffset, y: -diagonalOffset),
      NSPoint(x: -diagonalOffset, y: diagonalOffset),
      NSPoint(x: diagonalOffset, y: -diagonalOffset),
      NSPoint(x: diagonalOffset, y: diagonalOffset),
    ]

    for offset in offsets {
      symbol.draw(
        in: rect.offsetBy(dx: offset.x, dy: offset.y),
        from: .zero,
        operation: .destinationOut,
        fraction: 1,
        respectFlipped: false,
        hints: nil
      )
    }

    symbol.draw(
      in: rect,
      from: .zero,
      operation: .sourceOver,
      fraction: 1,
      respectFlipped: false,
      hints: nil
    )
  }

  private static func drawInsideForeground(
    _ layout: InsideForegroundLayout,
    symbolOperation: NSCompositingOperation
  ) {
    layout.percentageText.draw(
      at: layout.percentagePoint,
      withAttributes: batteryTextAttributes
    )
    if let symbolImage = layout.symbolImage,
      let symbolRect = layout.symbolRect
    {
      symbolImage.draw(
        in: symbolRect,
        from: .zero,
        operation: symbolOperation,
        fraction: 1,
        respectFlipped: false,
        hints: nil
      )
    }
  }

  private static func fillRect(_ rect: NSRect, with color: NSColor) {
    color.setFill()
    NSBezierPath(
      roundedRect: rect,
      xRadius: Layout.outsideFillCornerRadius,
      yRadius: Layout.outsideFillCornerRadius
    ).fill()
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
          chargingMode: .charging,
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
        HStack(spacing: 20) {
          ForEach([100, 75, 60, 60, 61, 40, 25, 15], id: \.self) {
            level in
            if let insideImg = BatteryRenderer.render(
              level: level,
              chargingMode: .charging,
              isLowPower: false,
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
        HStack(spacing: 20) {
          ForEach([100, 75, 60, 60, 61, 40, 25, 15], id: \.self) {
            level in
            if let insideImg = BatteryRenderer.render(
              level: level,
              chargingMode: .pluggedIn,
              isLowPower: false,
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
