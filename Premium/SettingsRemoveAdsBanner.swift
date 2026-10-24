//
//  SettingsRemoveAdsBanner.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 23/1/26.
//
import SwiftUI
import StoreKit

/// Settings card for users who still see ads. Every feature is free —
/// the one-time Remove Ads purchase is the only thing it offers.
struct SettingsRemoveAdsBanner: View {

    @EnvironmentObject var premium: PremiumStoreViewModel
    @EnvironmentObject var uiAccent: UIAccentStore

    let onTap: () -> Void

    var body: some View {
        VStack(spacing: 16) {

            // Title
            HStack(spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(.white.opacity(0.2)))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "remove_ads_banner_title"))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)

                    Text(String(localized: "remove_ads_banner_subtitle"))
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.88))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            // CTA
            Button(action: onTap) {
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
        // Products load lazily — fetch them so the button can show the price.
        .task {
            if premium.removeAdsProduct == nil { premium.start() }
        }
    }

    private var ctaTitle: String {
        guard let product = premium.removeAdsProduct else {
            return String(localized: "remove_ads")
        }
        return String(format: String(localized: "remove_ads_cta_format"), product.displayPrice)
    }
}
