//
//  5.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 20/1/26.
//
import SwiftUI

struct OnboardingWebBookingSlide: View {

    let onNext: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {

            // MARK: - Background
            LinearGradient(
                colors: scheme == .light
                    ? [
                        Color(.systemBackground),
                        Color.accentColor.opacity(0.06)
                      ]
                    : [
                        Color.onboardingDarkBackground,
                        Color.onboardingDarkBackground.opacity(0.9)
                      ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {

                // MARK: - Header
                WebBookingHeader()

                Spacer(minLength: 12)

                // MARK: - Phone mock
                WebBookingPhoneMock()
                    .padding(.top, -30)

                Spacer()

                // MARK: - CTA
                Button {
                    onNext()
                } label: {
                    Text(String(localized: "onboarding_next"))
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(18)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
            }
        }
    }
}

struct WebBookingHeader: View {

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {

            RoundedRectangle(cornerRadius: 40)
                .fill(
                    scheme == .light
                    ? Color(.secondarySystemBackground)
                    : Color.onboardingDarkCard
                )
                .frame(height: 260)
                .offset(y: -80)

            VStack(spacing: 14) {

                HStack(spacing: 8) {
                    Image(systemName: "link.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Color.accentColor)

                    Text("Easy Schedule")
                        .font(.system(size: 16, weight: .semibold))
                }

                Text(String(localized: "onboarding_web_booking_title"))
                    .font(.system(size: 34, weight: .bold))
                    .tracking(-0.8)
                    .multilineTextAlignment(.center)

                Text(String(localized: "onboarding_web_booking_subtitle"))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Text(String(localized: "onboarding_no_app_required"))
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        Capsule().fill(
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


struct WebBookingPhoneMock: View {

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {

            // Shadow
            RoundedRectangle(cornerRadius: 38)
                .fill(Color.black.opacity(scheme == .light ? 0.08 : 0.3))
                .blur(radius: 30)
                .frame(width: 260, height: 520)
                .offset(y: 20)

            // Phone
            RoundedRectangle(cornerRadius: 38)
                .fill(
                    scheme == .light
                    ? Color(.tertiarySystemFill)
                    : Color(red: 22/255, green: 26/255, blue: 32/255)
                )
                .frame(width: 260, height: 520)

            RoundedRectangle(cornerRadius: 32)
                .fill(
                    scheme == .light
                    ? Color(.systemBackground)
                    : Color(red: 18/255, green: 22/255, blue: 28/255)
                )
                .frame(width: 246, height: 506)

            VStack(spacing: 14) {
                Spacer()

                Text("easyschedule.app/yourname")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)

                Text(String(localized: "mock_select_time"))
                    .font(.system(size: 15, weight: .medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.accentColor.opacity(0.15))
                    .cornerRadius(14)

                Text(String(localized: "mock_confirm_booking"))
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)

                Spacer()
            }
            .frame(width: 246, height: 506)
        }
    }
}
