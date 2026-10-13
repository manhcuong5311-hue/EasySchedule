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
                        .onboardingCTALabel()
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

                Text(String(localized: "onboarding_booking_link_title"))
                    .font(.system(size: 34, weight: .bold))
                    .tracking(-0.8)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 20)

                Text(String(localized: "onboarding_booking_link_subtitle"))
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

                // Memorable link in a browser-style address bar
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10, weight: .semibold))
                    Text(verbatim: BookingLink.handlePrefix + String(localized: "onboarding_mock_handle"))
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(
                        scheme == .light
                        ? Color(.secondarySystemBackground)
                        : Color.onboardingDarkCard
                    )
                )
                .padding(.horizontal, 14)

                // Booking hours
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.system(size: 12, weight: .semibold))
                    Text(verbatim: "\(String(localized: "onboarding_mock_weekdays")) · \(OnboardingMock.range(9, 0, 18, 0))")
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .foregroundColor(Color.accentColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(Color.accentColor.opacity(scheme == .light ? 0.12 : 0.22))
                )

                Text(String(localized: "mock_select_time"))
                    .font(.system(size: 15, weight: .medium))
                    .padding(.top, 6)

                // Free slots (one picked)
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        slotChip(OnboardingMock.time(9), selected: false)
                        slotChip(OnboardingMock.time(10, 30), selected: false)
                        slotChip(OnboardingMock.time(13), selected: false)
                    }
                    HStack(spacing: 8) {
                        slotChip(OnboardingMock.time(14, 30), selected: true)
                        slotChip(OnboardingMock.time(16), selected: false)
                        slotChip(OnboardingMock.time(17), selected: false)
                    }
                }
                .padding(.horizontal, 16)

                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(String(localized: "mock_confirm_booking"))
                        .foregroundColor(.secondary)
                }
                .font(.system(size: 14))
                .padding(.top, 4)

                Spacer()
            }
            .frame(width: 246, height: 506)
        }
    }

    private func slotChip(_ label: String, selected: Bool) -> some View {
        Text(verbatim: label)
            .font(.system(size: 12, weight: selected ? .semibold : .medium))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .foregroundColor(selected ? .white : .primary)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        selected
                        ? Color.accentColor
                        : Color.accentColor.opacity(scheme == .light ? 0.10 : 0.18)
                    )
            )
    }
}
