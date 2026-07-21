import Defaults
import SwiftUI

/// Same underlying logic as `GeneralSettingsView`'s "Launch at login" toggle
/// — no new behavior, just a friendlier presentation for onboarding.
struct OnboardingLoginItemStep: View {
    @Default(.launchAtLogin) private var launchAtLogin

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            OnboardingStepHeader(
                icon: "power",
                title: "Launch at Login",
                subtitle: "Stasis works best running quietly in the background from the moment you log in."
            )

            OnboardingToggleRow(
                title: "Launch Stasis at login",
                description: "Starts automatically after you log in — no need to open it by hand.",
                isOn: $launchAtLogin
            )

            HStack(spacing: 10) {
                OnboardingHighlightCard(
                    icon: "menubar.rectangle",
                    title: "Menu Bar Only",
                    subtitle: "No Dock icon, no clutter"
                )
                OnboardingHighlightCard(
                    icon: "gearshape.2",
                    title: "Change Anytime",
                    subtitle: "Toggle it off in General"
                )
            }

            Spacer()
        }
        .onChange(of: launchAtLogin) { _, newValue in
            LaunchAtLoginService.shared.setLaunchAtLogin(newValue)
        }
    }
}
