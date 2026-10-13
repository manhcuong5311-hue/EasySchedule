//
//  SettingsProBanner.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 23/1/26.
//
import SwiftUI
import Combine
import Foundation
import StoreKit

extension Notification.Name {
    static let OpenPaywall = Notification.Name("OpenPaywall")
}

struct SettingsPremiumBanner: View {

    @EnvironmentObject var premium: PremiumStoreViewModel
    @EnvironmentObject var uiAccent: UIAccentStore

    /// A free-trial intro offer the user can actually redeem. nil → no trial is
    /// advertised anywhere on the banner (none is configured in App Store Connect today).
    @State private var trialOffer: TrialOffer?

    private struct TrialOffer: Equatable {
        /// "7-day free trial" — built from the real offer period.
        let trialText: String
        /// "499.000 ₫ · Billed annually" — what is charged after the trial.
        let priceText: String
    }

    var body: some View {
        VStack(spacing: 16) {

            // Title
            HStack(spacing: 14) {
                Image(systemName: premium.tier == .premium ? "crown.fill" : "star.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(.white.opacity(0.2)))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(bannerTitleKey)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)

                    Text(bannerSubtitleKey)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.88))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            // CTA
            Button {
                handleCTA()
            } label: {
                Text(ctaTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(uiAccent.color)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 14)
                    .background(Capsule().fill(Color.white))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(premium.loading)
            .opacity(premium.loading ? 0.6 : 1)

            // Trial terms — only when a real, redeemable trial exists.
            if premium.tier == .free, let trialOffer {
                Text(verbatim: "\(trialOffer.trialText) · \(trialOffer.priceText)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [
                    uiAccent.color,
                    uiAccent.color.opacity(0.78)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: AppRadius.panel, style: .continuous)
        )
        .task(id: trialCheckID) { await resolveTrialOffer() }
    }


    private func handleCTA() {
        switch premium.tier {
        case .free:
            if trialOffer != nil {
                // Real trial available → start it (StoreKit sheet shows the terms).
                premium.startFreeTrial()
            } else {
                // No trial → open the regular upgrade flow.
                NotificationCenter.default.post(name: .OpenPaywall, object: nil)
            }

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

    // MARK: - Trial detection
    //
    // Same rule as PremiumUpgradeSheet.trialText(for:) — Premium products only,
    // intro offer with paymentMode == .freeTrial — and the same product
    // PremiumStore.startFreeTrial() would buy, plus StoreKit's eligibility check.

    private var trialCheckID: String {
        "\(premium.tier.rawValue)|" + premium.products.map(\.id).joined(separator: ",")
    }

    private func resolveTrialOffer() async {
        guard premium.tier == .free,
              let product = premium.products.first(where: { $0.isPremium && $0.hasFreeTrial }),
              let subscription = product.subscription,
              let offer = subscription.introductoryOffer,
              let text = Self.trialText(for: offer)
        else {
            trialOffer = nil
            return
        }

        let eligible = await subscription.isEligibleForIntroOffer
        guard !Task.isCancelled else { return }

        trialOffer = eligible
            ? TrialOffer(trialText: text, priceText: Self.priceText(for: product, subscription))
            : nil
    }

    private static func trialText(for offer: Product.SubscriptionOffer) -> String? {
        guard offer.paymentMode == .freeTrial else { return nil }
        let value = offer.period.value
        switch offer.period.unit {
        case .day:
            return String(format: String(localized: "trial_days_format"), value)
        case .week:
            return String(format: String(localized: "trial_days_format"), value * 7)
        case .month:
            return String(format: String(localized: "trial_months_format"), value)
        default:
            return nil
        }
    }

    private static func priceText(for product: Product,
                                  _ subscription: Product.SubscriptionInfo) -> String {
        switch subscription.subscriptionPeriod.unit {
        case .year:
            return "\(product.displayPrice) · \(String(localized: "paywall_billed_annually"))"
        case .month:
            return "\(product.displayPrice) · \(String(localized: "paywall_billing_monthly"))"
        default:
            return product.displayPrice
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

    private var ctaTitle: String {
        switch premium.tier {
        case .free:
            return trialOffer != nil
                ? String(localized: "start_free_trial")
                : String(localized: "settings_banner_upgrade")
        case .premium:
            return String(localized: "premium_banner_cta_premium")
        case .pro:
            return ""
        }
    }
}
