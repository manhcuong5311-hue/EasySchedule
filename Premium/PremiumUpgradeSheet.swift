// PremiumUpgradeSheet.swift
//

import SwiftUI
import StoreKit

struct PremiumUpgradeSheet: View {

    @EnvironmentObject var premium: PremiumStoreViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.requestReview) private var requestReview

    let preselectProductID: String?
    let autoPurchase: Bool

    @State private var selectedPlan: PlanType = .premium
    @State private var selectedProduct: Product? = nil
    @State private var purchaseError: String? = nil
    @State private var isLoading = false

    private var currentTier: PremiumTier { premium.tier }

    // Premium palette — self-contained so the sheet looks the same wherever it's
    // presented (no dependency on the app's accent environment object).
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
        .onChange(of: selectedPlan) { _, _ in syncSelectedProduct() }
        .onChange(of: premium.products.count) { _, _ in syncSelectedProduct() }
        .onAppear(perform: handleAppear)
        .alert(
            String(localized: "purchase_error"),
            isPresented: Binding(
                get: { purchaseError != nil },
                set: { _ in purchaseError = nil }
            )
        ) {
            Button(String(localized: "ok"), role: .cancel) {}
        } message: {
            Text(purchaseError ?? "")
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

            Text(String(localized: "paywall_headline"))
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            Text(String(localized: "upgrade_premium_subtitle"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if currentTier != .free {
                Label(
                    currentTier == .pro
                    ? String(localized: "pro_activated")
                    : String(localized: "premium_activated"),
                    systemImage: currentTier == .pro ? "crown.fill" : "star.fill"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(currentTier == .pro ? .orange : brand)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill((currentTier == .pro ? Color.orange : brand).opacity(0.12))
                )
            }
        }
    }

    // MARK: - Content (toggle + benefits + plans / state)

    @ViewBuilder
    private var content: some View {
        if currentTier == .pro {
            subscribedView(title: "pro_active_note")
        } else {
            VStack(spacing: 22) {
                tierToggle
                benefitsCard

                if currentTier == .premium && selectedPlan == .premium {
                    subscribedView(title: "premium_active_note")
                } else if premium.products.isEmpty {
                    ProgressView(String(localized: "loading_packages"))
                        .padding(.vertical, 40)
                        .task { premium.start() }
                } else {
                    planCards
                }
            }
        }
    }

    // MARK: - Tier toggle

    private var tierToggle: some View {
        HStack(spacing: 6) {
            ForEach(PlanType.allCases, id: \.self) { plan in
                tierButton(plan)
            }
        }
        .padding(4)
        .background(Capsule().fill(Color(.systemGray6)))
    }

    private func tierButton(_ plan: PlanType) -> some View {
        let isSelected = selectedPlan == plan
        let disabled = currentTier == .pro
            || (currentTier == .premium && plan == .premium)
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { selectedPlan = plan }
        } label: {
            Text(plan.displayName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(tierButtonBackground(isSelected))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
    }

    @ViewBuilder
    private func tierButtonBackground(_ isSelected: Bool) -> some View {
        if isSelected {
            Capsule().fill(brandGradient)
        } else {
            Color.clear
        }
    }

    // MARK: - Benefits

    private var benefitRows: [FeatureRow] {
        [.eventsPerDay, .advanceDays, .chat, .todo, .offDays, .sync]
    }

    private var benefitsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(benefitRows, id: \.self) { row in
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(brand)
                    Text(featureTitle(row))
                        .font(.subheadline)
                    Spacer()
                    benefitValue(row)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
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

    @ViewBuilder
    private func benefitValue(_ row: FeatureRow) -> some View {
        let limits = planData[selectedPlan]!
        switch row {
        case .eventsPerDay:
            Text("\(limits.eventsPerDay)")
        case .advanceDays:
            Text(String(format: String(localized: "days_suffix"), "\(limits.advanceDays)"))
        case .chat:
            Text(limits.chatPerEvent.map { "\($0)" } ?? String(localized: "unlimited"))
        case .todo:
            Text("\(limits.todosPerEvent)")
        default:
            EmptyView()
        }
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
                    if isYearly {
                        Text(String(format: String(localized: "paywall_per_month_approx"),
                                    perMonthText(product)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let trial = trialText(for: product) {
                        Text(trial)
                            .font(.caption)
                            .foregroundStyle(.green)
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
                    let ok = await premium.restore()
                    isLoading = false
                    if ok { dismiss() } else { purchaseError = String(localized: "restore_failed") }
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

    // MARK: - Subscribed state

    @ViewBuilder
    func subscribedView(title: String.LocalizationValue) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.largeTitle)
                .foregroundColor(.green)
            Text(String(localized: title))
                .font(.headline)
            Text(String(localized: "subscription_active_note"))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 36)
    }

    // MARK: - Derived product data

    private var tierKey: String { selectedPlan == .premium ? "premium" : "pro" }
    private var tierProducts: [Product] {
        premium.products.filter { $0.id.contains(tierKey) }
    }
    private var monthlyProduct: Product? {
        tierProducts.first { $0.id.contains("monthly") }
    }
    private var yearlyProduct: Product? {
        tierProducts.first { $0.id.contains("yearly") }
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

    private var canPurchase: Bool {
        if currentTier == .pro { return false }
        if currentTier == .premium && selectedPlan == .premium { return false }
        return true
    }

    private var showCTA: Bool {
        canPurchase && !premium.products.isEmpty && selectedProduct != nil
    }

    private var ctaTitle: String {
        if let product = selectedProduct, trialText(for: product) != nil {
            return String(localized: "start_free_trial")
        }
        return String(localized: "continue")
    }

    // MARK: - Actions

    private func syncSelectedProduct() {
        if let sel = selectedProduct, tierProducts.contains(where: { $0.id == sel.id }) { return }
        selectedProduct = yearlyProduct ?? monthlyProduct
    }

    private func purchase(_ product: Product) async {
        isLoading = true
        let success = await premium.buy(product)
        isLoading = false

        if success {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                ReviewManager.shared.requestAfterPremiumUpgrade(requestReview)
            }
            dismiss()
        } else {
            purchaseError = String(localized: "payment_failed")
        }
    }

    private func handleAppear() {
        if currentTier == .premium { selectedPlan = .pro }

        Task {
            if !premium.isLoaded {
                premium.start()
                while !premium.isLoaded {
                    try? await Task.sleep(nanoseconds: 150_000_000)
                }
            }

            if let id = preselectProductID {
                selectedPlan = id.contains("premium") ? .premium : .pro
                if let product = premium.products.first(where: { $0.id == id }) {
                    selectedProduct = product
                    if autoPurchase {
                        await purchase(product)
                        return
                    }
                }
            }

            syncSelectedProduct()
        }
    }

    // MARK: - Trial helper (Apple-safe)

    private func trialText(for product: Product) -> String? {
        // Free trial is a Premium-tier perk only — Pro never advertises a trial,
        // so the Pro CTA always reads "Continue", never "Start free trial".
        guard product.id.contains("premium") else { return nil }

        guard
            let subscription = product.subscription,
            let intro = subscription.introductoryOffer,
            intro.paymentMode == .freeTrial
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

// MARK: - Plan model

enum PlanType: String, CaseIterable {
    case premium = "Premium"
    case pro = "Pro"

    /// Localized tier name for display. Logic still keys off the enum case /
    /// rawValue, so this is presentation-only.
    var displayName: String {
        switch self {
        case .premium: return String(localized: "plan_premium")
        case .pro:     return String(localized: "plan_pro")
        }
    }
}

enum FeatureRow: CaseIterable {
    case eventsPerDay
    case advanceDays
    case members
    case chat
    case todo
    case offDays
    case busyHours
    case sync
}

func featureTitle(_ row: FeatureRow) -> LocalizedStringKey {
    switch row {
    case .eventsPerDay: return "feature_events_per_day"
    case .advanceDays:  return "feature_advance_days"
    case .members:      return "feature_members"
    case .chat:         return "feature_chat"
    case .todo:         return "feature_todo"
    case .offDays:      return "feature_off_days"
    case .busyHours:    return "feature_busy_hours"
    case .sync:         return "feature_sync"
    }
}

struct PlanLimits {
    let eventsPerDay: Int
    let advanceDays: Int
    let chatPerEvent: Int?        // nil = unlimited
    let todosPerEvent: Int
    let unlimitedOffDays: Bool
    let unlimitedBusyHours: Bool
    let syncOnline: Bool
}

let planData: [PlanType: PlanLimits] = [
    .premium: PlanLimits(
        eventsPerDay: 20,
        advanceDays: 90,
        chatPerEvent: 500,
        todosPerEvent: 20,
        unlimitedOffDays: true,
        unlimitedBusyHours: true,
        syncOnline: true
    ),
    .pro: PlanLimits(
        eventsPerDay: 50,
        advanceDays: 270,
        chatPerEvent: nil,   // unlimited
        todosPerEvent: 50,
        unlimitedOffDays: true,
        unlimitedBusyHours: true,
        syncOnline: true
    )
]
