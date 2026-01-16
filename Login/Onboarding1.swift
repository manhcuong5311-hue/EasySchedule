
import SwiftUI
import Combine

enum OnboardingStep: Int {
    case hero = 0
    case availability
    case chat
    case planning
    case cta
}
extension Color {
    static let onboardingDarkBackground = Color(red: 14/255, green: 17/255, blue: 22/255)
    static let onboardingDarkCard = Color(red: 28/255, green: 31/255, blue: 38/255)
}

struct OnboardingHeroSlide: View {
    
    let onNext: () -> Void
    
    @Environment(\.colorScheme) private var scheme
    
    var body: some View {
        ZStack {

            // MARK: - Background
            LinearGradient(
                colors: scheme == .light
                    ? [
                        Color(.systemBackground),
                        Color.accentColor.opacity(0.08)
                      ]
                    : [
                        Color.onboardingDarkBackground,
                        Color.onboardingDarkBackground.opacity(0.85)
                      ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {

                // MARK: - Curved Header (TypeAI style)
                CurvedHeader()

                Spacer(minLength: 12)

                // MARK: - iPhone Mock
                AvailabilityPhoneMock1()
                    .padding(.top, -40)

                Spacer()

                // MARK: - CTA
                VStack(spacing: 14) {

                    Button {
                        onNext() 
                    } label: {
                        Text(String(localized: "onboarding_get_started"))
                            .font(.system(size: 17, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(18)
                    }

                    Text(String(localized: "onboarding_legal"))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
            }
        }
    }
}

struct CurvedHeader: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack {

            // Curved background
            RoundedRectangle(cornerRadius: 40)
                .fill(
                    scheme == .light
                    ? Color(.secondarySystemBackground)
                    : Color.onboardingDarkCard
                )

                .frame(height: 260)
                .offset(y: -80)

            VStack(spacing: 14) {

                // App name / icon (nhẹ)
                HStack(spacing: 8) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Color.accentColor)

                    Text("Easy Schedule")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                }

                // Big title
                Text(String(localized: "onboarding_shared_availability_title"))                    .font(.system(size: 34, weight: .bold))
                    .tracking(-0.8)

                // Pill badge
                Text(String(localized: "onboarding_realtime_sync"))
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(
                                scheme == .light
                                ? Color(.secondarySystemBackground)
                                : Color.onboardingDarkCard.opacity(0.85)
                            )


                    )
                    .overlay(
                        Capsule()
                            .stroke(Color.accentColor.opacity(0.8), lineWidth: 1.5)
                    )
                    .foregroundColor(Color.accentColor)

            }
            .padding(.top, 40)
            .offset(y: -40)
        }
    }
}

struct AvailabilityPhoneMock1: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack {

            // Shadow
            RoundedRectangle(cornerRadius: 38)
                .fill(Color.black.opacity(scheme == .light ? 0.08 : 0.3))
                .blur(radius: 30)
                .frame(width: 260, height: 520)
                .offset(y: 20)

            // Phone body
            RoundedRectangle(cornerRadius: 38)
                .fill(
                    scheme == .light
                    ? Color(.tertiarySystemFill)
                    : Color(red: 22/255, green: 26/255, blue: 32/255)
                )

                .frame(width: 260, height: 520)

            // Screen
            RoundedRectangle(cornerRadius: 32)
                .fill(
                    scheme == .light
                    ? Color(.systemBackground)
                    : Color(red: 18/255, green: 22/255, blue: 28/255)
                )

                .frame(width: 246, height: 506)

            // Fake UI content
            VStack(spacing: 12) {
                Spacer()

                Text(String(localized: "mock_busy_time"))

                    .font(.system(size: 15, weight: .medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Color.accentColor.opacity(scheme == .light ? 0.15 : 0.25)
                    )
                    .cornerRadius(12)

                Text(String(localized: "mock_updated_now"))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                Spacer()
            }
            .frame(width: 246, height: 506)
        }
    }
}


