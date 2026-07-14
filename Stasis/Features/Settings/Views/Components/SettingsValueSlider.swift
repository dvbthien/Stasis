import SwiftUI

struct SettingsValueSlider: View {
  let title: LocalizedStringKey
  @Binding var value: Int
  let range: ClosedRange<Int>
  let step: Int
  let valueLabel: (Int) -> String

  init(
    _ title: LocalizedStringKey,
    value: Binding<Int>,
    range: ClosedRange<Int>,
    step: Int = 1,
    valueLabel: @escaping (Int) -> String
  ) {
    self.title = title
    self._value = value
    self.range = range
    self.step = step
    self.valueLabel = valueLabel
  }

  var body: some View {
    LabeledContent {
      HStack(spacing: SettingsLayout.controlSpacing) {
        Slider(
          value: Binding(
            get: { Double(value) },
            set: { value = Int($0) }
          ),
          in: Double(range.lowerBound)...Double(range.upperBound),
          step: Double(step)
        )

        Text(valueLabel(value))
          .monospacedDigit()
          .foregroundStyle(.secondary)
          .frame(width: SettingsLayout.trailingValueWidth, alignment: .trailing)
      }
    } label: {
      Text(title)
    }
  }
}
