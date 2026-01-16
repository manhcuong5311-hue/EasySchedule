//
//  2.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 16/1/26.
//


import SwiftUI
import Combine

struct AvailabilityFeatureSlide: View {
    
    let onNext: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {

            // Background giống TypeAI
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


            VStack(spacing: 16) {

                Text(String(localized: "availability_glance_title"))
                    .font(.system(size: 36, weight: .bold))
                    .tracking(-0.8)
                    .multilineTextAlignment(.center)

                Text(String(localized: "availability_glance_subtitle"))
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)


                Spacer()

                // MARK: - Phone + Floating bubbles
                ZStack {

                    AvailabilityPhoneMock2()

                    FloatingAvailabilityBubble(
                        title: String(localized: "availability_busy"),
                        subtitle: String(localized: "availability_busy_time"),
                        color: Color.accentColor,
                        x: -80,
                        y: -60
                    )

                    FloatingAvailabilityBubble(
                        title: String(localized: "availability_available"),
                        subtitle: String(localized: "availability_after_time"),
                        color: .green,
                        x: 70,
                        y: 80   // ⬅️ trước là 40
                    )


                }
                .frame(height: 420)

                Spacer()

                // MARK: - Next button
                Button {
                    onNext()
                } label: {
                    Text(String(localized: "common_next"))
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(18)
                        .shadow(
                            color: Color.black.opacity(scheme == .light ? 0.15 : 0.4),
                            radius: 10,
                            y: 6
                        )

                }

            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
    }
}

struct AvailabilityPhoneMock2: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
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

            VStack(spacing: 12) {
                Spacer()

                Text(String(localized: "availability_today"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)

                Text(String(localized: "mock_busy_time"))
                    .font(.system(size: 16, weight: .medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Color.accentColor.opacity(scheme == .light ? 0.15 : 0.25)
                    )
                    .cornerRadius(12)


                Spacer()
            }
        }
        .shadow(color: .black.opacity(0.15), radius: 30, y: 18)
    }
}

struct FloatingAvailabilityBubble: View {
    @Environment(\.colorScheme) private var scheme

    let title: String
    let subtitle: String
    let color: Color
    let x: CGFloat
    let y: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {

            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)

            Text(subtitle)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.95))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    scheme == .light
                    ? color
                    : color.opacity(0.85)
                )
        )

        .shadow(
            color: color.opacity(scheme == .light ? 0.35 : 0.55),
            radius: 14,
            y: 8
        )

        .offset(x: x, y: y)
    }
}

