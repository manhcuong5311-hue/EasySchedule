//
//  3.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 16/1/26.
//


import SwiftUI
import Combine

/// "Agree on a time, together" — a proposal card (2/3 agreed) between two chat
/// bubbles: confirm, suggest another time or vote; the event moves on majority.
struct OnboardingAgreeSlide: View {
    let onNext: () -> Void
    @Environment(\.colorScheme) private var scheme

    private var proposer: String { String(localized: "onboarding_mock_name_lina") }
    private var voter: String { String(localized: "onboarding_mock_name_alex") }
    private var timeRange: String { OnboardingMock.range(15, 0, 16, 0) }

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

                Text(String(localized: "onboarding_agree_title"))
                    .font(.system(size: 36, weight: .bold))
                    .tracking(-0.8)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.75)

                Text(String(localized: "onboarding_agree_subtitle"))
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)


                Spacer(minLength: 8)

                VStack(spacing: 16) {

                    // Proposer asks to move the event (top-left)
                    ChatUserBubble(
                        tag: proposer,
                        text: String(format: String(localized: "chat_auto_proposed_format"), timeRange),
                        highlight: timeRange,
                        x: 0,
                        y: 0
                    )
                    .frame(maxWidth: 270, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Proposal card — the visual focus
                    OnboardingProposalMockCard(
                        proposer: proposer,
                        timeRange: timeRange
                    )

                    // Someone votes yes (bottom-right)
                    ChatUserBubble(
                        tag: voter,
                        text: String(format: String(localized: "chat_auto_vote_yes_format"), timeRange, 2, 3),
                        highlight: nil,
                        x: 0,
                        y: 0
                    )
                    .frame(maxWidth: 280, alignment: .trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }

                Spacer(minLength: 8)

                Button {
                    onNext()
                } label: {
                    Text(String(localized: "common_next"))
                        .onboardingCTALabel()
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 40)       // clears the top-trailing "Skip"
            .padding(.bottom, 28)
        }
    }
}


/// Mock of the in-app time-change proposal: "<name> suggests …", a vote
/// progress bar and the Agree / New time actions.
struct OnboardingProposalMockCard: View {
    @Environment(\.colorScheme) private var scheme

    let proposer: String
    let timeRange: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "clock.arrow.2.circlepath")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Color.accentColor)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle().fill(Color.accentColor.opacity(scheme == .light ? 0.12 : 0.22))
                    )

                Text(highlightedProposal)
                    .font(.system(size: 15, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: 2, total: 3)
                    .progressViewStyle(.linear)
                    .tint(Color.accentColor)

                Text(String(format: String(localized: "proposal_tally_format"), 2, 3, 2))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 10) {
                Text(String(localized: "response_propose"))
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundColor(.primary)
                    .background(
                        Capsule().fill(
                            scheme == .light
                            ? Color(.systemGray6)
                            : Color.white.opacity(0.08)
                        )
                    )

                HStack(spacing: 6) {
                    Image(systemName: "hand.thumbsup.fill")
                        .font(.system(size: 13, weight: .semibold))
                    Text(String(localized: "proposal_accept"))
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .foregroundColor(.white)
                .background(Capsule().fill(Color.accentColor))
            }
        }
        .padding(16)
        .frame(maxWidth: 330)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(
                    scheme == .light
                    ? Color.white
                    : Color.onboardingDarkCard
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.accentColor.opacity(scheme == .light ? 0.25 : 0.35), lineWidth: 1)
                )
                .shadow(
                    color: Color.accentColor.opacity(scheme == .light ? 0.18 : 0.35),
                    radius: 14,
                    y: 8
                )
        )
    }

    private var highlightedProposal: AttributedString {
        var result = AttributedString(
            String(format: String(localized: "proposal_other_format"), proposer, timeRange)
        )
        if let range = result.range(of: timeRange) {
            result[range].foregroundColor = Color.accentColor
        }
        return result
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
