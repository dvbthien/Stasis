import SwiftUI
import Defaults

/// The onboarding card itself: a small step flow shown once, on first run,
/// walking the user through enabling battery management and Launch at Login.
struct OnboardingView: View {
    var onDismiss: () -> Void

    @State private var step: OnboardingStep = .welcome

    private var stepIndex: Int { step.rawValue }
    private var isLastStep: Bool { step == OnboardingStep.allCases.last }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            Group {
                switch step {
                case .welcome:
                    OnboardingWelcomeStep()
                case .batteryManagement:
                    OnboardingBatteryManagementStep(onReady: goToNextStep)
                case .loginItem:
                    OnboardingLoginItemStep()
                case .completion:
                    OnboardingCompletionStep(onFinish: finish)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(20)

            if !isLastStep {
                footer
            }
        }
        .background(OnboardingCardBackground())
        .frame(width: 460, height: 420)
    }

    private var header: some View {
        HStack {
            Text("Welcome to Stasis")
                .font(.subheadline.weight(.semibold))

            Spacer()

            OnboardingStepDots(currentStep: stepIndex, totalSteps: OnboardingStep.allCases.count)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var footer: some View {
        HStack {
            if step != .welcome {
                Button("Back", action: goToPreviousStep)
                    .buttonStyle(OnboardingSecondaryButtonStyle())
            }

            Button("Skip", action: finish)
                .buttonStyle(OnboardingSecondaryButtonStyle())

            Spacer()

            Button(step == .welcome ? "Get Started" : "Continue", action: goToNextStep)
                .buttonStyle(OnboardingPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private func goToPreviousStep() {
        guard let previous = OnboardingStep(rawValue: step.rawValue - 1) else { return }
        withAnimation(.easeInOut(duration: 0.2)) { step = previous }
    }

    private func goToNextStep() {
        guard let next = OnboardingStep(rawValue: step.rawValue + 1) else { return }
        withAnimation(.easeInOut(duration: 0.2)) { step = next }
    }

    private func finish() {
        Defaults[.hasCompletedOnboarding] = true
        onDismiss()
    }
}

private struct OnboardingWelcomeStep: View {
    var body: some View {
        VStack(spacing: 14) {
            Spacer()

            Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 64, height: 64)

            Text("Let's set up Stasis")
                .font(.title2.bold())

            Text("This takes under a minute — Stasis manages your Mac's charging and can run quietly in the background from login.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Spacer()
        }
    }
}

private struct OnboardingCompletionStep: View {
    var onFinish: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Spacer()

            Image(systemName: "checkmark.seal.fill")
                .font(.system(.largeTitle, weight: .semibold))
                .foregroundStyle(Color.accentColor)

            Text("Stasis is ready")
                .font(.title2.bold())

            Text("You can fine-tune everything else in Settings at any time.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()

            Button("Get Started", action: onFinish)
                .buttonStyle(OnboardingPrimaryButtonStyle())
        }
    }
}
