//
//  4.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 16/1/26.
//


import SwiftUI
import Combine
struct SmartPlanningAISlide: View {
    let onNext: () -> Void

    var body: some View {
        ZStack {

            LinearGradient(
                colors: [
                    Color.white,
                    Color.accentColor.opacity(0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {

                Text(String(localized: "smart_planning_title"))
                    .font(.system(size: 36, weight: .bold))
                    .tracking(-0.8)
                    .multilineTextAlignment(.center)

                Text(String(localized: "smart_planning_subtitle"))
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)


                Spacer()

                // MARK: - Feature cards
                ZStack {

                    TimeFeatureCard(
                        icon: "calendar.badge.minus",
                        title: String(localized: "feature_day_off_title"),
                        subtitle: String(localized: "feature_day_off_subtitle"),
                        color: .orange,
                        x: -60,
                        y: -60
                    )

                    TimeFeatureCard(
                        icon: "clock.badge.checkmark",
                        title: String(localized: "feature_busy_hours_title"),
                        subtitle: String(localized: "feature_busy_hours_subtitle"),
                        color: .accentColor,
                        x: 60,
                        y: -40
                    )

                    TimeFeatureCard(
                        icon: "bubble.left.and.bubble.right.fill",
                        title: String(localized: "feature_chat_title"),
                        subtitle: String(localized: "feature_chat_subtitle"),
                        color: .green,
                        x: -40,
                        y: 60
                    )

                    TimeFeatureCard(
                        icon: "paintpalette.fill",
                        title: String(localized: "feature_colors_title"),
                        subtitle: String(localized: "feature_colors_subtitle"),
                        color: .purple,
                        x: 40,
                        y: 90
                    )

                }
                .frame(height: 340)

                Spacer()

                // MARK: - Next
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
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
    }
}


struct ContextCard: View {

    var body: some View {
        HStack(alignment: .top, spacing: 12) {

            Image(systemName: "calendar")
                .font(.system(size: 22))
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "context_meeting_title"))
                    .font(.system(size: 15, weight: .semibold))

                Text(String(localized: "context_meeting_subtitle"))
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.06), radius: 16, y: 8)
        )
        .padding(.horizontal, 6)
    }
}

struct TimeFeatureCard: View {

    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let x: CGFloat
    let y: CGFloat

    var body: some View {
        HStack(spacing: 12) {

            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundColor(color)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))

                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.06), radius: 12, y: 6)
        )
        .offset(x: x, y: y)
    }
}


struct OptionRow: View {

    let title: String
    let options: [String]
    let selected: String
    var icon: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            Text(title)
                .font(.system(size: 14))
                .foregroundColor(.secondary)

            HStack(spacing: 10) {
                ForEach(options, id: \.self) { option in
                    HStack(spacing: 6) {

                        if let icon, option == selected {
                            Image(systemName: icon)
                                .font(.system(size: 12))
                        }

                        Text(option)
                            .font(.system(size: 14, weight: .medium))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(
                                option == selected
                                ? Color.accentColor.opacity(0.15)
                                : Color(.systemGray6)
                            )
                    )
                    .overlay(
                        Capsule()
                            .stroke(
                                option == selected
                                ? Color.accentColor
                                : Color.clear
                            )
                    )
                }
            }
        }
    }
}

