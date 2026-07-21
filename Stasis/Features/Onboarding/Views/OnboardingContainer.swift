import SwiftUI

/// Wraps `content` with a first-run onboarding card. The wrapped content
/// keeps its identity and state (e.g. `SettingsView`'s sidebar selection)
/// across the overlay showing and hiding — this blurs/disables it rather
/// than swapping it out for a conditional branch.
struct OnboardingContainer<Content: View>: View {
    @Binding var showOnboarding: Bool
    let content: Content

    init(showOnboarding: Binding<Bool>, @ViewBuilder content: () -> Content) {
        _showOnboarding = showOnboarding
        self.content = content()
    }

    var body: some View {
        ZStack {
            content
                .blur(radius: showOnboarding ? 6 : 0)
                .disabled(showOnboarding)

            if showOnboarding {
                OnboardingView(
                    onDismiss: {
                        withAnimation { showOnboarding = false }
                    }
                )
                .transition(.scale(scale: 0.98).combined(with: .opacity))
                .zIndex(1)
            }
        }
    }
}
