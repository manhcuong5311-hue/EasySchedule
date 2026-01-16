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
    var body: some View {
        ZStack {

            // Background giống TypeAI
            LinearGradient(
                colors: [
                    Color.white,
                    Color.accentColor.opacity(0.06)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 16) {

                Text("See availability\nat a glance")
                    .font(.system(size: 36, weight: .bold))
                    .tracking(-0.8)
                    .multilineTextAlignment(.center)

                Text("Busy hours and off days update in real time.\nNo back-and-forth messages.")
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)


                Spacer()

                // MARK: - Phone + Floating bubbles
                ZStack {

                    AvailabilityPhoneMock2()

                    // Floating bubble 1
                    FloatingAvailabilityBubble(
                        title: "Busy",
                        subtitle: "2:00 – 4:00 PM",
                        color: Color.accentColor,
                        x: -80,
                        y: -60
                    )

                    // Floating bubble 2
                    FloatingAvailabilityBubble(
                        title: "Available",
                        subtitle: "After 4:00 PM",
                        color: .green,
                        x: 70,
                        y: 40
                    )
                }
                .frame(height: 420)

                Spacer()

                // MARK: - Next button
                Button {
                    onNext()
                } label: {
                    Text("Next")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(18)
                }

            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
    }
}

struct AvailabilityPhoneMock2: View {

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 38)
                .fill(Color.black)
                .frame(width: 260, height: 520)

            RoundedRectangle(cornerRadius: 32)
                .fill(Color(.systemBackground))
                .frame(width: 246, height: 506)

            VStack(spacing: 12) {
                Spacer()

                Text("Today")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)

                Text("Busy 2:00 – 4:00 PM")
                    .font(.system(size: 16, weight: .medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.accentColor.opacity(0.15))
                    .cornerRadius(12)

                Spacer()
            }
        }
        .shadow(color: .black.opacity(0.15), radius: 30, y: 18)
    }
}

struct FloatingAvailabilityBubble: View {

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
                .fill(color)
        )
        .shadow(color: color.opacity(0.35), radius: 14, y: 8)
        .offset(x: x, y: y)
    }
}

