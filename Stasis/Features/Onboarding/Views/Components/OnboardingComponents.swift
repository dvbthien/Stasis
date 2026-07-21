import SwiftUI

/// Card chrome behind the onboarding flow, distinct from the window's own
/// background so it reads as a modal sitting above the blurred Settings
/// content.
struct OnboardingCardBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(.regularMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.25), radius: 24, y: 12)
    }
}

struct OnboardingStepDots: View {
    let currentStep: Int
    let totalSteps: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<totalSteps, id: \.self) { index in
                Capsule()
                    .fill(index <= currentStep ? Color.accentColor : Color.secondary.opacity(0.25))
                    .frame(width: 18, height: 4)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: currentStep)
    }
}

struct OnboardingPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 13)
            .padding(.vertical, 5)
            .foregroundStyle(.white)
            .background(Color.accentColor, in: Capsule())
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

struct OnboardingSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.footnote.weight(.medium))
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .foregroundStyle(.secondary)
    }
}

/// Generic rounded card surface used behind rows/panels within a step.
struct OnboardingSurface: View {
    var cornerRadius: CGFloat = 12
    var fillColor: Color = Color(nsColor: .controlBackgroundColor)
    var strokeColor: Color = Color.primary.opacity(0.08)

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(fillColor)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(strokeColor, lineWidth: 0.5)
            )
    }
}

/// Small icon badge used next to a step's title.
struct OnboardingIconBadge: View {
    let symbol: String

    var body: some View {
        ZStack {
            OnboardingSurface(cornerRadius: 10)
                .frame(width: 40, height: 40)

            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.accentColor)
        }
    }
}

/// Title row at the top of a step: icon badge + bold title + secondary
/// subtitle. Uses macOS's built-in text styles (`.title3`, `.subheadline`)
/// rather than fixed point sizes, per the HIG's typography guidance, so the
/// hierarchy stays consistent with the rest of Settings and scales with
/// Dynamic Type.
struct OnboardingStepHeader: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            OnboardingIconBadge(symbol: icon)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.title3.bold())

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }
}

/// A tinted status card: icon + title + description, used for success,
/// error, and "waiting" states so they read at a glance rather than as a
/// line of small text.
struct OnboardingStatusCard: View {
    let icon: String
    let title: String
    let description: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(OnboardingSurface(cornerRadius: 12, fillColor: tint.opacity(0.1), strokeColor: tint.opacity(0.25)))
    }
}

/// One numbered line inside a guidance panel (e.g. approval instructions).
struct OnboardingNumberedRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number)")
                .font(.caption2.bold())
                .foregroundStyle(Color.accentColor)
                .frame(width: 16, height: 16)
                .background(Circle().fill(Color.accentColor.opacity(0.12)))

            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A titled panel of numbered guidance rows.
struct OnboardingGuidancePanel: View {
    let title: String
    let rows: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                OnboardingNumberedRow(number: index + 1, text: row)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OnboardingSurface())
    }
}

/// One tile in a row of feature highlights — icon on top, short title,
/// shorter caption. Meant to fill out a step with concrete facts about what
/// the toggle above actually does, not decorative padding.
struct OnboardingHighlightCard: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.accentColor)

            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .background(OnboardingSurface())
    }
}

/// A card-style toggle row: title + description on the left, switch on the
/// right — reads as a feature you're turning on, not a form field.
struct OnboardingToggleRow: View {
    let title: String
    let description: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(14)
        .background(OnboardingSurface())
    }
}
