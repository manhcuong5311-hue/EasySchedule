//
//  SettingsProBanner.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 23/1/26.
//
import SwiftUI
import Combine
import Foundation

extension Notification.Name {
    static let OpenPaywall = Notification.Name("OpenPaywall")
}

struct SettingsPremiumBanner: View {

    @EnvironmentObject var premium: PremiumStoreViewModel
    @EnvironmentObject var uiAccent: UIAccentStore

    var body: some View {
        VStack(spacing: 14) {

            // Title
            HStack(spacing: 12) {
                Image(systemName: premium.tier == .premium ? "crown.fill" : "star.fill")
                    .font(.system(size: 26))
                    .foregroundColor(.white)

                VStack(alignment: .leading, spacing: 4) {
                    Text(bannerTitleKey)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)

                    Text(bannerSubtitleKey)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                }

                Spacer()
            }

            // CTA
            Button {
                handleCTA()
            } label: {
                Text(bannerCTAKey)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(uiAccent.color)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.white)
                    .clipShape(Capsule())
            }
            .disabled(premium.loading)
            .opacity(premium.loading ? 0.6 : 1)
            if premium.tier == .free {
                Text("premium_trial_7_days")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.85))
            }
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [
                    uiAccent.color.opacity(0.95),
                    uiAccent.color.opacity(0.75)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(22)
    }

    
    private func handleCTA() {
        switch premium.tier {
        case .free:
            // ✅ Try Free → start trial NGAY
            premium.startFreeTrial()

        case .premium:
            // 👉 Upgrade → mở paywall
            NotificationCenter.default.post(
                name: .OpenPaywall,
                object: nil
            )

        case .pro:
            break
        }
    }

    // MARK: - Localization keys theo tier
    private var bannerTitleKey: LocalizedStringKey {
        switch premium.tier {
        case .free: return "premium_banner_title_free"
        case .premium: return "premium_banner_title_premium"
        case .pro: return ""
        }
    }

    private var bannerSubtitleKey: LocalizedStringKey {
        switch premium.tier {
        case .free: return "premium_banner_subtitle_free"
        case .premium: return "premium_banner_subtitle_premium"
        case .pro: return ""
        }
    }

    private var bannerCTAKey: LocalizedStringKey {
        switch premium.tier {
        case .free: return "premium_banner_cta_free"
        case .premium: return "premium_banner_cta_premium"
        case .pro: return ""
        }
    }
}
