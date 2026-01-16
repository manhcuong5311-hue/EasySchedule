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

                Text("Turn chats into\nclear plans")
                    .font(.system(size: 36, weight: .bold))
                    .tracking(-0.8)
                    .multilineTextAlignment(.center)

                Text("Messages become tasks.\nEverything stays linked to time.")
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                Spacer()

                ZStack {

                    // User chat
                    ChatUserBubble(
                        tag: "User",
                        text: "Can we meet at 3?",
                        highlight: nil,
                        x: -40,
                        y: -80
                    )

                    // Other user response
                    ChatUserBubble(
                        tag: "User",
                        text: "Meeting at 3:00 PM",
                        highlight: "3:00 PM",
                        x: 40,
                        y: 0
                    )

                    // Todo
                    TodoUserBubble(
                        text: "Prepare agenda – 3:00 PM",
                        x: -10,
                        y: 90
                    )
                }
                .frame(height: 340)

                Spacer()

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




struct TodoUserBubble: View {

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
                .fill(Color.accentColor.opacity(0.12))
        )
        .shadow(color: .accentColor.opacity(0.25), radius: 12, y: 6)
        .offset(x: x, y: y)
    }
}


struct ChatUserBubble: View {

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
                .background(Color(.systemGray5))
                .foregroundColor(.secondary)
                .cornerRadius(8)

            Text(highlightedText)
                .font(.system(size: 15))
                .foregroundColor(.primary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color(.systemGray4))
                )
        )
        .shadow(color: .black.opacity(0.06), radius: 12, y: 6)
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
