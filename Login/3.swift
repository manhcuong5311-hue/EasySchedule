//
//  3.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 16/1/26.
//


import SwiftUI
import Combine

struct ChatToPlanAISlide: View {
    let onNext: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {

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
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()


            VStack(spacing: 18) {

                Text(String(localized: "chat_to_plan_title"))
                    .font(.system(size: 36, weight: .bold))
                    .tracking(-0.8)
                    .multilineTextAlignment(.center)

                Text(String(localized: "chat_to_plan_subtitle"))
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)


                Spacer()

                ZStack {

                    ChatUserBubble(
                        tag: String(localized: "chat_tag_user"),
                        text: String(localized: "chat_message_question"),
                        highlight: nil,
                        x: -40,
                        y: -80
                    )

                    ChatUserBubble(
                        tag: String(localized: "chat_tag_user"),
                        text: String(localized: "chat_message_confirm"),
                        highlight: String(localized: "chat_time_3pm"),
                        x: 40,
                        y: 0
                    )


                    // Todo
                    TodoUserBubble(
                        text: String(localized: "chat_todo_prepare"),
                        x: -10,
                        y: 90
                    )

                }
                .frame(height: 340)

                Spacer()

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




struct TodoUserBubble: View {
    @Environment(\.colorScheme) private var scheme

    let text: String
    let x: CGFloat
    let y: CGFloat

    var body: some View {
        HStack(spacing: 10) {

            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(Color.accentColor)

            Text(text)
                .font(.system(size: 15, weight: .medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(
                    Color.accentColor.opacity(scheme == .light ? 0.12 : 0.22)
                )
                .shadow(
                    color: Color.accentColor.opacity(scheme == .light ? 0.25 : 0.45),
                    radius: 12,
                    y: 6
                )
)
        .offset(x: x, y: y)
    }
}


struct ChatUserBubble: View {
    @Environment(\.colorScheme) private var scheme

    let tag: String
    let text: String
    let highlight: String?
    let x: CGFloat
    let y: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {

            Text(tag)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            scheme == .light
                            ? Color(.systemGray5)
                            : Color.onboardingDarkCard.opacity(0.8)
                        )
                )
                .foregroundColor(.secondary)
                .cornerRadius(8)

            Text(highlightedText)
                .font(.system(size: 15))
                .foregroundColor(.primary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(
                    scheme == .light
                    ? Color.white
                    : Color.onboardingDarkCard
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(
                            scheme == .light
                            ? Color(.systemGray4)
                            : Color.white.opacity(0.06)
                        )
                )

        )
        .shadow(
            color: Color.black.opacity(scheme == .light ? 0.06 : 0.35),
            radius: 12,
            y: 6
        )

        .offset(x: x, y: y)
    }

    private var highlightedText: AttributedString {
        var result = AttributedString(text)
        if let highlight {
            if let range = result.range(of: highlight) {
                result[range].backgroundColor = Color.accentColor.opacity(0.18)
            }
        }
        return result
    }
}
