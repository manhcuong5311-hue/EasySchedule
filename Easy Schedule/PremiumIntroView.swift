//
//  PremiumIntroView.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 16/12/25.
//
import SwiftUI

struct PremiumIntroView: View {
    @Binding var isPresented: Bool

    @State private var canSkip = false
    @State private var showCard = false
    @State private var animateCrown = false
    let onUpgrade: () -> Void
    
    var body: some View {
        ZStack {
            // Background dim
            Color.black.opacity(showCard ? 0.45 : 0)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.25), value: showCard)

            VStack {
                Spacer()

                VStack(spacing: 20) {

                    // 👑 Crown (pulse nhẹ)
                    Image(systemName: "crown.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.yellow, .orange],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .scaleEffect(animateCrown ? 1.08 : 1.0)
                        .animation(
                            .easeInOut(duration: 1.3)
                                .repeatForever(autoreverses: true),
                            value: animateCrown
                        )

                    Text(String(localized: "premium_intro_title"))
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)

                    VStack(alignment: .leading, spacing: 12) {
                        PremiumFeatureRow(
                            icon: "calendar.badge.clock",
                            text: String(localized: "premium_feature_180_days")
                        )
                        PremiumFeatureRow(
                            icon: "bolt.fill",
                            text: String(localized: "premium_feature_30_events")
                        )
                        PremiumFeatureRow(
                            icon: "person.2.fill",
                            text: String(localized: "premium_feature_shared")
                        )
                        PremiumFeatureRow(
                              icon: "bubble.left.and.bubble.right.fill",
                              text: String(localized: "premium_feature_unlimited_chat")
                          )
                        PremiumFeatureRow(
                            icon: "checklist",
                            text: String(localized: "premium_feature_more_todos")
                        )

                    }
                    .padding(.top, 4)

                    Button {
                        // 👉 mở paywall
                        isPresented = false
                        onUpgrade()    
                    } label: {
                        Text(String(localized: "premium_upgrade"))
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(
                                LinearGradient(
                                    colors: [Color.accentColor, Color.accentColor.opacity(0.85)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .foregroundColor(.white)
                            .cornerRadius(16)
                    }
                    .padding(.top, 10)

                    Button {
                        isPresented = false
                    } label: {
                        Text(String(localized: "premium_skip"))
                            .foregroundColor(.secondary)
                    }
                    .disabled(!canSkip)
                    .opacity(canSkip ? 1 : 0)
                    .offset(y: canSkip ? 0 : 6)
                    .animation(.easeOut(duration: 0.25), value: canSkip)
                }
                .padding(28)
                .background(
                    RoundedRectangle(cornerRadius: 30)
                        .fill(Color(.systemBackground))
                        .shadow(color: .black.opacity(0.18), radius: 24, y: 12)
                )
                .padding(.horizontal)
                .scaleEffect(showCard ? 1.0 : 0.92)
                .opacity(showCard ? 1 : 0)
                .animation(
                    .spring(response: 0.5, dampingFraction: 0.85),
                    value: showCard
                )

                Spacer()
            }
        }
        .onAppear {
            showCard = true
            animateCrown = true

            // ⏱ Mở nút Skip sau 3s
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                canSkip = true
            }
        }
    }
}

// MARK: - Feature Row
struct PremiumFeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.accentColor)
                .frame(width: 24)

            Text(text)
                .font(.subheadline)
        }
    }
}

import Foundation

enum PremiumIntroGate {

    /// Key lưu lần cuối đã hiện Premium Intro
    private static let lastShownKey = "PremiumIntro_LastShown"

    /// Chỉ cho hiện Premium Intro 1 lần / ngày
    static func shouldShowToday() -> Bool {
        let defaults = UserDefaults.standard

        // Chưa từng hiện → cho hiện
        guard let lastShown = defaults.object(forKey: lastShownKey) as? Date else {
            return true
        }

        // Hôm nay chưa hiện → cho hiện
        return !Calendar.current.isDateInToday(lastShown)
    }

    /// Đánh dấu đã hiện hôm nay
    static func markShown() {
        UserDefaults.standard.set(Date(), forKey: lastShownKey)
    }

    /// (Optional) Reset – dùng cho debug
    static func reset() {
        UserDefaults.standard.removeObject(forKey: lastShownKey)
    }
}
