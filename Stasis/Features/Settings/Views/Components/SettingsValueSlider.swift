import SwiftUI

struct SettingsValueSlider: View {
  let title: LocalizedStringKey
  @Binding var value: Int
  let range: ClosedRange<Int>
  let step: Int
  let valueLabel: (Int) -> String
  let onEditingChanged: (Bool) -> Void

  init(
    _ title: LocalizedStringKey,
    value: Binding<Int>,
    range: ClosedRange<Int>,
    step: Int = 1,
    valueLabel: @escaping (Int) -> String,
    onEditingChanged: @escaping (Bool) -> Void = { _ in }
  ) {
    self.title = title
    self._value = value
    self.range = range
    self.step = step
    self.valueLabel = valueLabel
    self.onEditingChanged = onEditingChanged
  }

  var body: some View {
    LabeledContent {
      HStack(spacing: SettingsLayout.controlSpacing) {
        Slider(
          value: Binding(
            get: { Double(value) },
            set: { newValue in
              let updatedValue = Int(newValue)
              guard updatedValue != value else { return }
              value = updatedValue
            }
          ),
          in: Double(range.lowerBound)...Double(range.upperBound),
          step: Double(step),
          onEditingChanged: { isEditing in
            handleEditingChanged(isEditing)
          }
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

  private func handleEditingChanged(_ isEditing: Bool) {
    onEditingChanged(isEditing)
  }
}
