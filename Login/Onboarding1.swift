
import SwiftUI
import Combine

enum OnboardingStep: Int {
    case hero = 0
    case availability
    case chat
    case planning
    case cta
}

struct OnboardingHeroSlide: View {
    let onNext: () -> Void
    var body: some View {
        ZStack {

            // MARK: - Background
            LinearGradient(
                colors: [
                    Color.white,
                    Color.accentColor.opacity(0.08)
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

    var body: some View {
        ZStack {

            // Curved background
            RoundedRectangle(cornerRadius: 40)
                .fill(Color.white)
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
                            .stroke(Color.accentColor, lineWidth: 1.5)
                    )
                    .foregroundColor(Color.accentColor)
            }
            .padding(.top, 40)
        }
    }
}

struct AvailabilityPhoneMock1: View {

    var body: some View {
        ZStack {

            // Shadow
            RoundedRectangle(cornerRadius: 38)
                .fill(Color.black.opacity(0.08))
                .blur(radius: 30)
                .frame(width: 260, height: 520)
                .offset(y: 20)

            // Phone body
            RoundedRectangle(cornerRadius: 38)
                .fill(Color.black)
                .frame(width: 260, height: 520)

            // Screen
            RoundedRectangle(cornerRadius: 32)
                .fill(Color(.systemBackground))
                .frame(width: 246, height: 506)

            // Fake UI content
            VStack(spacing: 12) {
                Spacer()

                Text(String(localized: "mock_busy_time"))

                    .font(.system(size: 15, weight: .medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.accentColor.opacity(0.15))
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


