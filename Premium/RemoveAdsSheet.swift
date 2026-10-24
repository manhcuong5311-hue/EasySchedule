// RemoveAdsSheet.swift
//
// The only purchase since 2.5: a one-time "Remove Ads". Every feature stays free.
//

import SwiftUI
import StoreKit

struct RemoveAdsSheet: View {

    @EnvironmentObject var premium: PremiumStoreViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.requestReview) private var requestReview

    @State private var isLoading = false
    @State private var restoreFailed = false

    // Same palette as the old upgrade sheet — self-contained so the sheet looks the
    // same wherever it's presented (no dependency on the app's accent environment object).
    private let brand = Color(red: 0.40, green: 0.45, blue: 0.96)
    private var brandGradient: LinearGradient {
        LinearGradient(
            colors: [Color(red: 0.42, green: 0.46, blue: 0.98),
                     Color(red: 0.58, green: 0.40, blue: 0.96)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    private let appleEULAURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    private let privacyPolicyURL = URL(string: "https://manhcuong5311-hue.github.io/easyschedule-privacy/")!

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 26) {
                hero
                content
                legalFooter
            }
            .padding(.horizontal, 20)
            .padding(.top, 52)
            .padding(.bottom, 16)
        }
        .background(backgroundView)
        .safeAreaInset(edge: .bottom) {
            if !premium.isAdFree { ctaBar }
        }
        .overlay(alignment: .topTrailing) { closeButton }
        .onAppear {
            AppAnalytics.log(AppAnalyticsEvent.paywallShown, ["kind": "remove_ads"])
            if premium.removeAdsProduct == nil { premium.start() }
        }
        .alert(String(localized: "restore_purchases"), isPresented: $restoreFailed) {
            Button(String(localized: "ok"), role: .cancel) {}
        } message: {
            Text(String(localized: "restore_failed"))
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: 12) {
            ZStack {
                // Soft brand glow so the light diamond pops on the pale background
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [brand.opacity(0.30), .clear],
                            center: .center, startRadius: 5, endRadius: 66
                        )
                    )
                    .frame(width: 132, height: 132)

                Image("number2")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 104, height: 104)
                    .shadow(color: brand.opacity(0.30), radius: 14, y: 8)
            }

            Text(String(localized: "remove_ads_sheet_title"))
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            Text(String(localized: "remove_ads_sheet_subtitle"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if premium.isAdFree {
            VStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.largeTitle)
                    .foregroundColor(.green)
                Text(String(localized: "ads_removed"))
                    .font(.headline)
                Text(String(localized: "ads_removed_thanks"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical, 36)
        } else {
            benefitsCard
        }
    }

    private var benefits: [(icon: String, key: String.LocalizationValue)] {
        [
            ("rectangle.slash", "remove_ads_benefit_no_ads"),
            ("bag", "remove_ads_benefit_one_time"),
            ("ipad.and.iphone", "remove_ads_benefit_devices"),
            ("heart", "remove_ads_benefit_support")
        ]
    }

    private var benefitsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(benefits, id: \.icon) { benefit in
                HStack(spacing: 12) {
                    Image(systemName: benefit.icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(brand)
                        .frame(width: 24)
                    Text(String(localized: benefit.key))
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    // MARK: - CTA bar (fixed bottom)

    private var ctaBar: some View {
        VStack(spacing: 0) {
            Button {
                guard let product = premium.removeAdsProduct else { return }
                Task { await purchase(product) }
            } label: {
                HStack(spacing: 8) {
                    if isLoading || premium.removeAdsProduct == nil {
                        ProgressView().tint(.white)
                    }
                    Text(ctaTitle).font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Capsule().fill(brandGradient))
                .foregroundStyle(.white)
                .shadow(color: brand.opacity(0.35), radius: 12, y: 6)
            }
            .buttonStyle(.plain)
            .disabled(isLoading || premium.removeAdsProduct == nil)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 6)
        .background(.ultraThinMaterial)
    }

    private var ctaTitle: String {
        guard let product = premium.removeAdsProduct else {
            return String(localized: "remove_ads")
        }
        return String(format: String(localized: "remove_ads_cta_format"), product.displayPrice)
    }

    // MARK: - Legal footer

    private var legalFooter: some View {
        VStack(spacing: 12) {
            Button {
                Task {
                    isLoading = true
                    let found = await premium.restore()
                    isLoading = false
                    if found { dismiss() } else { restoreFailed = true }
                }
            } label: {
                Text(String(localized: "restore_purchases"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(brand)
            }
            .disabled(isLoading)

            Text(String(localized: "remove_ads_legal_note"))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                Link(String(localized: "privacy_policy"), destination: privacyPolicyURL)
                    .underline()
                Link(String(localized: "terms_of_use"), destination: appleEULAURL)
                    .underline()
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    private var backgroundView: some View {
        LinearGradient(
            stops: [
                .init(color: brand.opacity(0.12), location: 0),
                .init(color: Color(.systemBackground), location: 0.3)
            ],
            startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var closeButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.title2)
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color(.systemGray), Color(.systemGray5))
        }
        .buttonStyle(.plain)
        .padding(16)
    }

    // MARK: - Actions

    private func purchase(_ product: Product) async {
        isLoading = true
        let success = await premium.buy(product)
        isLoading = false

        // false = cancelled / pending / failed — StoreKit already showed its own UI,
        // so the sheet just stays open for another try.
        guard success else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            ReviewManager.shared.requestAfterPremiumUpgrade(requestReview)
        }
        dismiss()
    }
}
