import AppKit
import Foundation
import SwiftUI

@MainActor
struct BatteryRenderer {

  // MARK: - 1. RENDER CACHE
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

    // Build the render context.
    let ctx = RenderContext(
      level: level,
      chargingMode: chargingMode,
      isLowPower: isLowPower,
      displayLocation: displayLocation,
      showState: showState
    )

    // Reuse an unchanged render.
    if ctx.stateKey == lastStateKey, let cachedImage = lastRenderedImage {
      return cachedImage
    }

    // Render at the target size.
    let finalImage = NSImage(size: ctx.targetSize, flipped: false) { rect in

      // Draw the outside percentage.
      if ctx.shouldShowOutsidePercentage {
        ctx.outsideText.draw(
          at: ctx.outsideTextPoint(in: rect),
          withAttributes: RenderContext.outsideAttributes
        )
      }

      // Share one layout across all layers.
      let bodyRect = ctx.bodyRect(in: rect)
      let plan = ctx.isInsideMode
        ? insidePlan(in: bodyRect, context: ctx)
        : nil

      // Draw the body and terminal.
      drawOutlineLayer(in: rect, bodyRect: bodyRect, plan: plan, context: ctx)

      // Draw the level fill.
      drawFillLayer(bodyRect: bodyRect, plan: plan, context: ctx)

      // Draw the foreground content.
      drawForegroundLayer(in: rect, plan: plan, context: ctx)

      return true
    }

    // Cache the result.
    lastStateKey = ctx.stateKey
    lastRenderedImage = finalImage

    return finalImage
  }
}

// MARK: - 3. RENDER STATE
extension BatteryRenderer {

  /// Shared drawing constants.
  private enum Layout {
    /// Matches the active status bar height to avoid scaling or clipping.
    static var canvasHeight: CGFloat {
      let thickness = NSStatusBar.system.thickness
      return thickness > 0 ? thickness : 22
    }

    static let insideBodyWidth: CGFloat = 28
    static let insideBodyHeight: CGFloat = 14
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

    static let insideTrackOpacity: CGFloat = 0.42
    static let outsideOutlineOpacity: CGFloat = 0.4
    static let outsideOutlineWidth: CGFloat = 1
    static let outsideFillInset: CGFloat = 1.5
    static let outsideFillCornerRadius: CGFloat = 1.5

    static let glyphAntialiasPadding: CGFloat = 0.25
    static let maximumGlyphSnapPercentage: CGFloat = 1
    static let symbolHaloRadius: CGFloat = 0.75

    static let fullBatteryLevel: CGFloat = 100
    static let criticalBatteryLevel = 20

    static let foregroundColor = NSColor.textColor
    /// Uses the icon tone at reduced opacity, matching the iOS empty track.
    static var insideTrackColor: NSColor {
      foregroundColor.withAlphaComponent(insideTrackOpacity)
    }
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
    /// Measured once; reused by layout, sizing, and positioning.
    let outsideTextSize: NSSize

    init(
      level: Int,
      chargingMode: ChargingMode,
      isLowPower: Bool,
      displayLocation: PercentageDisplayLocation,
      showState: Bool
    ) {
      self.level = level
      self.chargingMode = chargingMode
      self.isLowPower = isLowPower
      self.displayLocation = displayLocation
      self.showState = showState
      self.outsideTextSize = "\(level)%".size(
        withAttributes: Self.outsideAttributes
      )
    }

    // State flags.
    var isInsideMode: Bool { displayLocation == .insideIcon }
    var shouldShowOutsidePercentage: Bool { displayLocation == .nextToIcon }
    var isCritical: Bool {
      showState && level <= Layout.criticalBatteryLevel
    }
    /// True when the fill uses a state color instead of the icon tone.
    var hasStateColor: Bool {
      isCritical || isLowPower || chargingMode == .charging
    }
    var usesPassthroughKnockout: Bool { !hasStateColor }

    // Mode-specific dimensions.
    var bodyWidth: CGFloat {
      isInsideMode ? Layout.insideBodyWidth : Layout.outsideBodyWidth
    }
    var bodyHeight: CGFloat {
      isInsideMode ? Layout.insideBodyHeight : Layout.outsideBodyHeight
    }
    var cornerRadius: CGFloat {
      isInsideMode ? Layout.insideCornerRadius : Layout.outsideCornerRadius
    }

    // Percentage text styling.
    var outsideText: String { "\(level)%" }
    static let outsideAttributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: Layout.outsideTextSize),
      .foregroundColor: Layout.foregroundColor,
    ]

    // Battery body origin.
    var batteryXOffset: CGFloat {
      if !isInsideMode && shouldShowOutsidePercentage {
        return Layout.batteryLeadingInset + outsideTextSize.width
          + Layout.outsideTextSpacing
      }
      return Layout.batteryLeadingInset
    }

    // Canvas size.
    var targetSize: NSSize {
      var width = bodyWidth + Layout.batteryLeadingInset
        + Layout.capSpacing + Layout.capWidth
      if shouldShowOutsidePercentage {
        width += outsideTextSize.width + Layout.outsideTextSpacing
      }
      return NSSize(width: width, height: Layout.canvasHeight)
    }

    // State color.
    var fillColor: NSColor {
      if isCritical { return Layout.criticalFillColor }
      if isLowPower { return Layout.lowPowerFillColor }
      if chargingMode == .charging { return Layout.chargingFillColor }
      return Layout.foregroundColor
    }

    // Render cache key.
    var stateKey: String {
      "\(level)_\(chargingMode)_\(isLowPower)_\(displayLocation)_\(showState)_\(NSApp.effectiveAppearance.name)_\(Layout.canvasHeight)"
    }

    // Outside text origin.
    func outsideTextPoint(in rect: NSRect) -> NSPoint {
      NSPoint(
        x: Layout.batteryLeadingInset,
        y: (rect.height - outsideTextSize.height) / 2
      )
    }

    // Center the body vertically.
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

// MARK: - 4. DRAWING LAYERS
extension BatteryRenderer {

  /// Draws the body and terminal.
  private static func drawOutlineLayer(
    in rect: NSRect,
    bodyRect: NSRect,
    plan: InsidePlan?,
    context: RenderContext
  ) {
    // Draw the body.
    if let plan {
      // Draw the track only in the unfilled region.
      if plan.fillWidth < bodyRect.width {
        fillInsideBody(
          bodyRect,
          fromX: bodyRect.minX + plan.fillWidth,
          toX: bodyRect.maxX,
          color: Layout.insideTrackColor,
          context: context
        )
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

    // Draw the terminal.
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

  /// Draws the level fill.
  private static func drawFillLayer(
    bodyRect: NSRect,
    plan: InsidePlan?,
    context: RenderContext
  ) {
    if let plan {
      if plan.fillWidth > 0 {
        fillInsideBody(
          bodyRect,
          fromX: bodyRect.minX,
          toX: bodyRect.minX + plan.fillWidth,
          color: context.fillColor,
          context: context
        )
      }
    } else {
      let fillWidth = max(
        0,
        (context.bodyWidth - Layout.outsideFillInset * 2)
          * CGFloat(context.level) / Layout.fullBatteryLevel
      )
      if fillWidth > 0 {
        // Inset the fill evenly.
        context.fillColor.setFill()
        NSBezierPath(
          roundedRect: NSRect(
            x: context.batteryXOffset + Layout.outsideFillInset,
            y: bodyRect.minY + Layout.outsideFillInset,
            width: fillWidth,
            height: context.bodyHeight - Layout.outsideFillInset * 2
          ),
          xRadius: Layout.outsideFillCornerRadius,
          yRadius: Layout.outsideFillCornerRadius
        ).fill()
      }
    }
  }

  /// Fills the body path clipped to a horizontal band; the body path
  /// preserves rounded corners at either end.
  private static func fillInsideBody(
    _ bodyRect: NSRect,
    fromX minX: CGFloat,
    toX maxX: CGFloat,
    color: NSColor,
    context: RenderContext
  ) {
    NSGraphicsContext.current?.saveGraphicsState()
    if minX > bodyRect.minX || maxX < bodyRect.maxX {
      NSBezierPath(
        rect: NSRect(
          x: minX,
          y: bodyRect.minY,
          width: maxX - minX,
          height: bodyRect.height
        )
      ).addClip()
    }
    color.setFill()
    insideBodyPath(bodyRect, context: context).fill()
    NSGraphicsContext.current?.restoreGraphicsState()
  }

  private static let batteryTextAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(
      ofSize: Layout.insideTextSize,
      weight: Layout.textWeight
    ),
    .foregroundColor: Layout.foregroundColor,
  ]

  /// Horizontal ink bounds used to keep the fill edge off a glyph.
  private struct GlyphZone {
    let range: ClosedRange<CGFloat>
  }

  private struct InsideForegroundLayout {
    let percentageText: String
    let percentagePoint: NSPoint
    let symbolImage: NSImage?
    let symbolRect: NSRect?
    let glyphZones: [GlyphZone]
  }

  /// Keeps all inside layers aligned.
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

  /// A configured symbol image with its visible glyph bounds. SF Symbol
  /// images include transparent margins that would skew optical centering.
  private struct StateSymbol {
    let image: NSImage
    let inkBounds: NSRect
  }

  private static var stateSymbolCache: [String: StateSymbol] = [:]

  private static func stateSymbol(
    for chargingMode: ChargingMode,
    pointSize: CGFloat
  ) -> StateSymbol? {
    guard let symbolName = chargingMode.symbolName else { return nil }

    let cacheKey = "\(symbolName)-\(pointSize)"
    if let cached = stateSymbolCache[cacheKey] {
      return cached
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
    guard let configured = symbol.withSymbolConfiguration(
      sizeConfiguration.applying(colorConfiguration)
    ) else {
      return nil
    }
    let entry = StateSymbol(
      image: configured,
      inkBounds: imageInkBounds(of: configured)
    )
    stateSymbolCache[cacheKey] = entry
    return entry
  }

  /// Scans the image alpha to find the visible glyph bounds, in image
  /// point coordinates. Runs once per symbol and size; results are cached
  /// with the symbol.
  private static func imageInkBounds(of image: NSImage) -> NSRect {
    let fullRect = NSRect(origin: .zero, size: image.size)
    var proposedRect = fullRect
    guard image.size.width > 0,
      let cgImage = image.cgImage(
        forProposedRect: &proposedRect,
        context: nil,
        hints: nil
      )
    else { return fullRect }

    let rep = NSBitmapImageRep(cgImage: cgImage)
    let scale = CGFloat(rep.pixelsWide) / image.size.width
    var minX = rep.pixelsWide
    var maxX = -1
    for x in 0..<rep.pixelsWide {
      for y in 0..<rep.pixelsHigh
      where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.03 {
        minX = min(minX, x)
        maxX = max(maxX, x)
        break
      }
    }
    guard maxX >= minX else { return fullRect }

    return NSRect(
      x: CGFloat(minX) / scale,
      y: 0,
      width: CGFloat(maxX - minX + 1) / scale,
      height: image.size.height
    )
  }

  /// Horizontal ink extent measured with device metrics.
  private static func inkBounds(of text: String) -> NSRect {
    text.boundingRect(
      with: NSSize(
        width: CGFloat.greatestFiniteMagnitude,
        height: CGFloat.greatestFiniteMagnitude
      ),
      options: [.usesDeviceMetrics],
      attributes: batteryTextAttributes
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
    let percentageInkBounds = inkBounds(of: percentageText)
    let symbol = stateSymbol(
      for: context.chargingMode,
      pointSize: Layout.insideSymbolSize
    )
    let symbolSpacing = symbol == nil ? 0 : Layout.symbolSpacing
    let symbolInkWidth = symbol?.inkBounds.width ?? 0
    let contentWidth =
      percentageInkBounds.width + symbolSpacing + symbolInkWidth
    let contentMinX = bodyRect.midX - contentWidth / 2
    let percentagePoint = NSPoint(
      x: contentMinX - percentageInkBounds.minX,
      y: bodyRect.midY - percentageSize.height / 2
    )
    // Position the image so its visible ink starts after the spacing.
    let symbolRect = symbol.map { symbol in
      NSRect(
        x: contentMinX + percentageInkBounds.width + symbolSpacing
          - symbol.inkBounds.minX,
        y: bodyRect.midY - symbol.image.size.height / 2,
        width: symbol.image.size.width,
        height: symbol.image.size.height
      )
    }

    var glyphZones: [GlyphZone] = []
    var characterOriginX = percentagePoint.x
    for character in percentageText {
      let characterText = String(character)
      let characterAdvance = characterText.size(
        withAttributes: batteryTextAttributes
      ).width
      let characterInkBounds = inkBounds(of: characterText)
      let paddedMinX = characterOriginX + characterInkBounds.minX
        - Layout.glyphAntialiasPadding
      let paddedMaxX = characterOriginX + characterInkBounds.maxX
        + Layout.glyphAntialiasPadding
      glyphZones.append(GlyphZone(range: paddedMinX...paddedMaxX))
      characterOriginX += characterAdvance
    }
    if let symbolRect, let symbol {
      let inkMinX = symbolRect.minX + symbol.inkBounds.minX
      let paddedMinX = inkMinX - Layout.glyphAntialiasPadding
      let paddedMaxX = inkMinX + symbol.inkBounds.width
        + Layout.glyphAntialiasPadding
      glyphZones.append(
        GlyphZone(range: paddedMinX...paddedMaxX)
      )
    }

    return InsideForegroundLayout(
      percentageText: percentageText,
      percentagePoint: percentagePoint,
      symbolImage: symbol?.image,
      symbolRect: symbolRect,
      glyphZones: mergedGlyphZones(glyphZones)
    )
  }

  private static func mergedGlyphZones(_ zones: [GlyphZone]) -> [GlyphZone] {
    var merged: [GlyphZone] = []
    for zone in zones.sorted(by: { $0.range.lowerBound < $1.range.lowerBound }) {
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
        )
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

  /// Snaps only near glyph edges, capped at 1% to preserve level accuracy.
  private static func insideFillWidth(
    in bodyRect: NSRect,
    layout: InsideForegroundLayout,
    context: RenderContext
  ) -> CGFloat {
    let rawFillWidth = min(
      max(
        0,
        context.bodyWidth * CGFloat(context.level)
          / Layout.fullBatteryLevel
      ),
      context.bodyWidth
    )
    guard context.usesPassthroughKnockout else { return rawFillWidth }

    let rawEdgeX = bodyRect.minX + rawFillWidth
    guard let zone = layout.glyphZones.first(where: {
      $0.range.contains(rawEdgeX)
    }) else {
      return rawFillWidth
    }

    let distanceToLeadingEdge = rawEdgeX - zone.range.lowerBound
    let distanceToTrailingEdge = zone.range.upperBound - rawEdgeX
    let snapDistance = min(distanceToLeadingEdge, distanceToTrailingEdge)
    let maximumSnapDistance = context.bodyWidth
      * Layout.maximumGlyphSnapPercentage / Layout.fullBatteryLevel
    guard snapDistance <= maximumSnapDistance else { return rawFillWidth }

    let snappedEdgeX = distanceToLeadingEdge <= distanceToTrailingEdge
      ? zone.range.lowerBound
      : zone.range.upperBound
    return min(max(snappedEdgeX - bodyRect.minX, 0), bodyRect.width)
  }

  /// Draws the inside percentage and status symbol.
  private static func drawForegroundLayer(
    in rect: NSRect,
    plan: InsidePlan?,
    context: RenderContext
  ) {
    if let plan {
      let layout = plan.layout

      // Apply the knockout blend mode.
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

    } else {
      // stateSymbol returns nil while discharging (no symbol name).
      guard let symbol = stateSymbol(
        for: context.chargingMode,
        pointSize: Layout.outsideSymbolSize
      ) else { return }
        // Center the visible ink, not the padded image.
      let symbolRect = NSRect(
        x: context.batteryXOffset
          + (context.bodyWidth - symbol.inkBounds.width) / 2
          - symbol.inkBounds.minX,
        y: rect.midY - symbol.image.size.height / 2,
        width: symbol.image.size.width,
        height: symbol.image.size.height
      )
      drawSymbolWithKnockoutHalo(symbol.image, in: symbolRect)
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

}

#Preview {
  VStack(alignment: .leading, spacing: 16) {
    // Standard display without a percentage.
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

    // Inside percentage with knockout.
    Group {
      Text("Chữ đục lỗ bên trong (.insideIcon)")
        .font(.headline).foregroundStyle(.secondary)

      ForEach(
        [ChargingMode.discharging, .charging, .pluggedIn],
        id: \.self
      ) { mode in
        HStack(spacing: 20) {
          ForEach(
            Array([100, 75, 60, 60, 61, 40, 25, 15].enumerated()),
            id: \.offset
          ) { _, level in
            if let insideImg = BatteryRenderer.render(
              level: level,
              chargingMode: mode,
              isLowPower: mode == .discharging && level == 75,
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
    }

    Divider()

    // Percentage next to the battery.
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
  // Simulate the menu bar background.
  .background(Color(NSColor.windowBackgroundColor))
  // Switch schemes to test dynamic colors.
  .preferredColorScheme(.dark)
}
