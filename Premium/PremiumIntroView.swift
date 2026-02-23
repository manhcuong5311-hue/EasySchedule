//
//  PremiumIntroView.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 16/12/25.
//
import SwiftUI



struct PremiumIntroView: View {

    @Binding var isPresented: Bool
    let onUpgrade: () -> Void

    @State private var showCard = false
    @State private var animateHero = false
    @State private var showClose = false

    var body: some View {
        ZStack {

            // 🔥 Background
            Color.black.opacity(showCard ? 0.5 : 0)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.3), value: showCard)

            VStack(spacing: 0) {

                Spacer()

                // =====================
                // HERO IMAGE (TOP)
                // =====================
                Image("2")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 260)
                    .scaleEffect(animateHero ? 1.05 : 1.0)
                    .animation(
                        .easeInOut(duration: 2)
                            .repeatForever(autoreverses: true),
                        value: animateHero
                    )
                    .padding(.bottom, -40)

                // =====================
                // CARD
                // =====================
                VStack(spacing: 22) {

                    Text(String(localized: "premium_intro_title"))
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)

                    VStack(alignment: .leading, spacing: 14) {

                        PremiumFeatureRow(
                            icon: "calendar.badge.clock",
                            text: String(localized: "premium_feature_extended_schedule")
                        )

                        PremiumFeatureRow(
                            icon: "bolt.fill",
                            text: String(localized: "premium_feature_higher_limits")
                        )

                        PremiumFeatureRow(
                            icon: "bubble.left.and.bubble.right.fill",
                            text: String(localized: "premium_feature_chat_access")
                        )

                        PremiumFeatureRow(
                            icon: "arrow.triangle.2.circlepath",
                            text: String(localized: "premium_feature_cloud_sync")
                        )
                    }

                    Button {
                        isPresented = false
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            onUpgrade()
                        }

                    } label: {
                        Text(String(localized: "premium_continue"))
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(
                                LinearGradient(
                                    colors: [Color.accentColor, Color.accentColor.opacity(0.8)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .foregroundColor(.white)
                            .cornerRadius(18)
                    }
                }
                .padding(30)
                .background(
                    RoundedRectangle(cornerRadius: 32)
                        .fill(Color(.systemBackground))
                        .shadow(color: .black.opacity(0.25), radius: 30, y: 15)
                )
                .padding(.horizontal, 20)
                .offset(y: showCard ? 0 : 120)
                .opacity(showCard ? 1 : 0)
                .animation(
                    .spring(response: 0.6, dampingFraction: 0.85),
                    value: showCard
                )

                Spacer()
            }

            // =====================
            // CLOSE BUTTON (2s delay)
            // =====================
            if showClose {
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            isPresented = false
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 36, height: 36)
                                .background(
                                    Circle()
                                        .fill(Color.white.opacity(0.2))
                                )
                        }
                        .padding(.trailing, 20)
                        .padding(.top, 60)
                    }
                    Spacer()
                }
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.25), value: showClose)
            }
        }
        .onAppear {
            animateHero = true

            withAnimation {
                showCard = true
            }

            // ⏱ Delay 2s mới hiện X
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                showClose = true
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
