// ProUpgradeSheet.swift
//
// The Pro subscription (monthly / yearly): higher limits for busy schedules and
// no ads while it's active. Every feature itself is free — see PremiumLimits.
//

import SwiftUI
import StoreKit

struct ProUpgradeSheet: View {

    @EnvironmentObject var premium: PremiumStoreViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.requestReview) private var requestReview

    @State private var selectedProduct: Product? = nil
    @State private var isLoading = false
    @State private var restoreFailed = false
    /// Pro products whose free trial this Apple ID can still redeem.
    @State private var trialEligibleIDs: Set<String> = []

    // Same palette as RemoveAdsSheet — self-contained so the sheet looks the same
    // wherever it's presented (no dependency on the app's accent environment object).
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
            if showCTA { ctaBar }
        }
        .overlay(alignment: .topTrailing) { closeButton }
        .onAppear {
            AppAnalytics.log(AppAnalyticsEvent.paywallShown, ["kind": "pro"])
            if premium.proProducts.isEmpty { premium.start() }
        }
        .task(id: premium.products.count) {
            syncSelectedProduct()
            await refreshTrialEligibility()
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

            Text(String(localized: "pro_sheet_title"))
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            Text(String(localized: "pro_sheet_subtitle"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if premium.isPro {
                Label(String(localized: "pro_activated"), systemImage: "crown.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.orange.opacity(0.12)))
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if premium.isPro {
            VStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.largeTitle)
                    .foregroundColor(.green)
                Text(String(localized: "pro_active_note"))
                    .font(.headline)
                Text(String(localized: "subscription_active_note"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical, 36)
        } else {
            VStack(spacing: 22) {
                comparisonCard

                if premium.proProducts.isEmpty {
                    ProgressView(String(localized: "loading_packages"))
                        .padding(.vertical, 40)
                } else {
                    planCards
                }
            }
        }
    }

    // MARK: - Free vs Pro

    private var comparisonCard: some View {
        let free = PremiumLimits.limits(for: .premium)
        let pro = PremiumLimits.limits(for: .pro)

        return VStack(spacing: 14) {
            HStack {
                Spacer()
                Text(String(localized: "free"))
                    .frame(width: 72)
                Text(String(localized: "plan_pro"))
                    .foregroundStyle(brand)
                    .frame(width: 72)
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(.secondary)

            comparisonRow("feature_events_per_day",
                          free: "\(free.maxEventsPerDay)",
                          pro: "\(pro.maxEventsPerDay)")
            comparisonRow("feature_advance_days",
                          free: daysText(free.maxBookingDaysAhead),
                          pro: daysText(pro.maxBookingDaysAhead))
            comparisonRow("feature_todo",
                          free: "\(free.maxTodosPerEvent)",
                          pro: "\(pro.maxTodosPerEvent)")

            HStack {
                Text(String(localized: "feature_no_ads"))
                    .font(.subheadline)
                Spacer()
                Image(systemName: "minus")
                    .foregroundStyle(.secondary)
                    .frame(width: 72)
                Image(systemName: "checkmark")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(brand)
                    .frame(width: 72)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func comparisonRow(_ titleKey: String.LocalizationValue, free: String, pro: String) -> some View {
        HStack {
            Text(String(localized: titleKey))
                .font(.subheadline)
            Spacer()
            Text(free)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 72)
            Text(pro)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(brand)
                .frame(width: 72)
        }
    }

    private func daysText(_ days: Int) -> String {
        String(format: String(localized: "days_suffix"), "\(days)")
    }

    // MARK: - Plan cards

    private var planCards: some View {
        VStack(spacing: 12) {
            if let yearly = yearlyProduct {
                planCard(yearly, title: String(localized: "paywall_billing_yearly"), isYearly: true)
            }
            if let monthly = monthlyProduct {
                planCard(monthly, title: String(localized: "paywall_billing_monthly"), isYearly: false)
            }
        }
    }

    private func planCard(_ product: Product, title: String, isYearly: Bool) -> some View {
        let selected = selectedProduct?.id == product.id
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { selectedProduct = product }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(selected ? brand : Color(.systemGray3))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(title).font(.headline)
                        if isYearly, let pct = savingsPercent {
                            Text(String(format: String(localized: "paywall_save_percent"), pct))
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.green))
                        }
                    }
                    if let trial = trialText(for: product) {
                        Text(trial)
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else if isYearly {
                        Text(String(format: String(localized: "paywall_per_month_approx"),
                                    perMonthText(product)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(product.displayPrice).font(.headline)
                    if isYearly {
                        Text(String(localized: "paywall_billed_annually"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(selected ? brand.opacity(0.08) : Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(selected ? brand : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - CTA bar (fixed bottom)

    private var ctaBar: some View {
        VStack(spacing: 0) {
            Button {
                guard let product = selectedProduct else { return }
                Task { await purchase(product) }
            } label: {
                HStack(spacing: 8) {
                    if isLoading { ProgressView().tint(.white) }
                    Text(ctaTitle).font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Capsule().fill(brandGradient))
                .foregroundStyle(.white)
                .shadow(color: brand.opacity(0.35), radius: 12, y: 6)
            }
            .buttonStyle(.plain)
            .disabled(isLoading || selectedProduct == nil)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 6)
        .background(.ultraThinMaterial)
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

            VStack(spacing: 4) {
                Text(String(localized: "payment_charged_info"))
                Text(String(localized: "subscription_auto_renews"))
                Text(String(localized: "manage_subscription_note"))
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                Link(String(localized: "privacy_policy"), destination: privacyPolicyURL)
                    .underline()
                Link(String(localized: "terms_of_use"), destination: appleEULAURL)
                    .underline()
                Button(String(localized: "manage_subscription")) {
                    if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                        UIApplication.shared.open(url)
                    }
                }
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

    // MARK: - Derived product data

    private var monthlyProduct: Product? {
        premium.proProducts.first { $0.id.hasSuffix(".monthly") }
    }
    private var yearlyProduct: Product? {
        premium.proProducts.first { $0.id.hasSuffix(".yearly") }
    }

    private var savingsPercent: Int? {
        guard let m = monthlyProduct, let y = yearlyProduct else { return nil }
        let yearlyIfMonthly = m.price * Decimal(12)
        guard yearlyIfMonthly > 0 else { return nil }
        let saved = (yearlyIfMonthly - y.price) / yearlyIfMonthly
        let pct = Int((saved as NSDecimalNumber).doubleValue * 100)
        return pct > 0 ? pct : nil
    }

    private func perMonthText(_ product: Product) -> String {
        (product.price / Decimal(12)).formatted(product.priceFormatStyle)
    }

    private var showCTA: Bool {
        !premium.isPro && selectedProduct != nil
    }

    private var ctaTitle: String {
        if let product = selectedProduct, trialText(for: product) != nil {
            return String(localized: "start_free_trial")
        }
        return String(localized: "continue")
    }

    // MARK: - Actions

    private func syncSelectedProduct() {
        if let sel = selectedProduct, premium.proProducts.contains(where: { $0.id == sel.id }) { return }
        selectedProduct = yearlyProduct ?? monthlyProduct
    }

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

    // MARK: - Free trial (only advertised when this Apple ID can still redeem it)

    private func refreshTrialEligibility() async {
        var eligible: Set<String> = []
        for product in premium.proProducts {
            guard let subscription = product.subscription,
                  subscription.introductoryOffer?.paymentMode == .freeTrial
            else { continue }
            if await subscription.isEligibleForIntroOffer {
                eligible.insert(product.id)
            }
        }
        trialEligibleIDs = eligible
    }

    private func trialText(for product: Product) -> String? {
        guard trialEligibleIDs.contains(product.id),
              let intro = product.subscription?.introductoryOffer
        else { return nil }

        let value = intro.period.value
        switch intro.period.unit {
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
}
