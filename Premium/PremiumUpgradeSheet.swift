// PremiumUpgradeSheet.swift
//

import SwiftUI
import StoreKit

struct PremiumUpgradeSheet: View {

    @EnvironmentObject var premium: PremiumStoreViewModel
    @Environment(\.dismiss) var dismiss
    @State private var selectedPlan: PlanType = .premium
    private var currentTier: PremiumTier {
        premium.tier
    }


    @State private var purchaseError: String? = nil
    @State private var isLoading = false

    // Apple standard EULA URL (default)
    private let appleEULAURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    // Replace with your app's privacy policy URL
    private let privacyPolicyURL = URL(string: "https://manhcuong5311-hue.github.io/easyschedule-privacy/")!

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {

                    // MARK: - Header
                    VStack(spacing: 10) {

                        Text(String(localized: "premium_title"))
                            .font(.headline)


                        Text(String(localized: "upgrade_premium_subtitle"))
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        if currentTier != .free {
                            Label(
                                currentTier == .pro
                                ? String(localized: "pro_activated")
                                : String(localized: "premium_activated"),
                                systemImage: currentTier == .pro ? "crown.fill" : "star.fill"
                            )
                            .foregroundColor(currentTier == .pro ? .orange : .yellow)
                            .font(.headline)
                            .padding(.top, 4)
                        }

                    }
                    .padding(.top, 20)
                    // MARK: - Plan Selector (Premium / Pro)
                    HStack(spacing: 12) {
                        ForEach(PlanType.allCases, id: \.self) { plan in
                            Button {
                                selectedPlan = plan
                            } label: {
                                Text(plan.rawValue)
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(
                                        selectedPlan == plan
                                        ? Color.blue.opacity(0.15)
                                        : Color.gray.opacity(0.1)
                                    )
                                    .cornerRadius(12)
                            }
                            .disabled(
                                currentTier == .pro ||
                                (currentTier == .premium && plan == .premium)
                            )
                            .opacity(
                                currentTier == .pro ||
                                (currentTier == .premium && plan == .premium)
                                ? 0.5 : 1
                            )

                        }
                    }
                    .padding(.horizontal)

                    // MARK: - Plan Comparison (Side by Side)
                    VStack(spacing: 12) {

                        // Header row
                        HStack {
                            Text("")
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Text(String(localized: "premium_label"))
                                .font(.caption.weight(.semibold))
                                .frame(width: 80)

                            Text(String(localized: "pro_label"))
                                .font(.caption.weight(.semibold))
                                .frame(width: 80)
                        }
                        .foregroundColor(.secondary)

                        Divider()

                        // Feature rows
                        ForEach(FeatureRow.allCases, id: \.self) { row in
                            HStack {

                                // Feature title
                                Text(featureTitle(row))
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                // Premium value
                                featureValue(row, plan: .premium)
                                    .frame(width: 80)

                                // Pro value
                                featureValue(row, plan: .pro)
                                    .frame(width: 80)
                            }
                            .font(.subheadline)
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(16)
                    .padding(.horizontal)


                    // MARK: - Product Cards
                    if currentTier == .pro {

                        // ✅ Pro: không mua thêm gì được
                        subscribedView(title: "pro_active_note")

                    }
                    else if currentTier == .premium && selectedPlan == .premium {

                        // ✅ Premium đang xem Premium → đã kích hoạt
                        subscribedView(title: "premium_active_note")

                    }
                    else if premium.products.isEmpty {

                        ProgressView(String(localized: "loading_packages"))
                            .padding(.vertical, 40)
                            .task { premium.start() }

                    }
                    else {

                        // ✅ Free, hoặc Premium đang xem Pro → cho mua
                        VStack(spacing: 18) {
                            ForEach(
                                premium.products.filter { product in
                                    switch selectedPlan {
                                    case .premium:
                                        return product.id.contains("premium")
                                    case .pro:
                                        return product.id.contains("pro")
                                    }
                                },
                                id: \.id
                            ) { product in
                                premiumCard(for: product)
                            }
                        }
                        .padding(.horizontal)
                    }


                    // MARK: - Restore Button
                    VStack(spacing: 8) {

                        Button {
                            Task {
                                isLoading = true
                                let ok = await premium.restore()
                                isLoading = false

                                if ok { dismiss() }
                                else { purchaseError = String(localized: "restore_failed") }
                            }
                        } label: {
                            Text(String(localized: "restore_purchases"))
                                .fontWeight(.medium)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                        .disabled(isLoading)

                        // Legal text
                        VStack(spacing: 8) {
                            Text(String(localized: "payment_charged_info"))
                            Text(String(localized: "subscription_auto_renews"))
                            Text(String(localized: "manage_subscription_note"))
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)

                        // MARK: - Legal Links (Privacy Policy + Terms of Use)
                        HStack(spacing: 16) {
                            // Privacy Policy (your app)
                            Link(destination: privacyPolicyURL) {
                                Text(String(localized: "privacy_policy"))
                                    .font(.caption)
                                    .underline()
                            }
                            // Terms of Use (Apple standard EULA)
                            Link(destination: appleEULAURL) {
                                Text(String(localized: "terms_of_use"))
                                    .font(.caption)
                                    .underline()
                            }
                        }
                        .foregroundColor(.secondary)
                        .padding(.top, 6)

                        Button(String(localized: "manage_subscription")) {
                            if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                                UIApplication.shared.open(url)
                            }
                        }
                        .font(.caption)
                        .padding(.top, 6)
                    }
                    .padding(.top, 10)

                    Button(String(localized: "close")) { dismiss() }
                        .foregroundColor(.secondary)
                        .padding(.top, 14)

                    Spacer().frame(height: 40)
                }
            }
            .onAppear {
                // ⭐ UX IMPROVEMENT
                if currentTier == .premium {
                    selectedPlan = .pro
                }
            }
            .alert(
                String(localized: "purchase_error"),
                isPresented: Binding(
                    get: { purchaseError != nil },
                    set: { _ in purchaseError = nil }
                )
            ) {
                Button(String(localized:"ok"), role: .cancel) {}
            } message: {
                Text(purchaseError ?? "")
            }
        }
    }
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
        .padding(.vertical, 40)
    }


    // MARK: - Premium Card UI
    private func premiumCard(for product: Product) -> some View {

        Button {
            guard currentTier != .pro else { return }

            Task {
                isLoading = true
                let success = await premium.buy(product)
                isLoading = false

                if success { dismiss() }
                else { purchaseError = String(localized: "payment_failed") }
            }
        } label: {

            VStack(alignment: .leading, spacing: 12) {

                // BEST VALUE badge for yearly
                // MARK: - Trial / Best Value Badge (Apple-safe)
                if let trial = trialText(for: product) {

                    // ✅ Chỉ hiện khi Apple xác nhận có Free Trial
                    Text(trial)
                        .font(.caption2.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.2))
                        .foregroundColor(.green)
                        .cornerRadius(6)

                } else if product.id.contains("yearly") {

                    // Fallback: Best value (không nhắc trial)
                    Text(String(localized: "best_value_save"))
                        .font(.caption2.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.2))
                        .foregroundColor(.green)
                        .cornerRadius(6)
                }


                HStack {

                    VStack(alignment: .leading, spacing: 6) {
                        Text(product.displayName)
                            .font(.headline)

                        Text(product.description)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Text(product.displayPrice)
                        .font(.title3.bold())
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.gray.opacity(0.12), lineWidth: 1)
            )
            .cornerRadius(18)
        }
        .buttonStyle(.plain)
        .opacity(isLoading ? 0.4 : 1)
        .disabled(isLoading || currentTier == .pro)
    }
    
    // MARK: - Trial Helper (Apple-safe)
    private func trialText(for product: Product) -> String? {

        guard
            let subscription = product.subscription,
            let intro = subscription.introductoryOffer,
            intro.paymentMode == .freeTrial
        else {
            return nil
        }

        let value = intro.period.value
        let unit = intro.period.unit

        switch unit {
        case .day:
            return String(
                format: String(localized: "trial_days_format"),
                value
            )

        case .week:
            return String(
                format: String(localized: "trial_days_format"),
                value * 7
            )

        case .month:
            return String(
                format: String(localized: "trial_months_format"),
                value
            )

        default:
            return nil
        }
    }


    
    @ViewBuilder
    func featureValue(_ row: FeatureRow, plan: PlanType) -> some View {

        let limits = planData[plan]!

        switch row {
        case .eventsPerDay:
            Text("\(limits.eventsPerDay)")

        case .advanceDays:
            Text(
                String(
                    format: String(localized: "days_suffix"),
                    "\(limits.advanceDays)"
                )
            )
        case .members:
            if plan == .premium {
                Text(String(localized: "members_invite_people"))
            } else {
                Text(String(localized: "members_plan_with_groups"))
            }



        case .chat:
            if let limit = limits.chatPerEvent {
                Text("\(limit)")
            } else {
                Text(String(localized: "unlimited"))
            }


        case .todo:
            Text("\(limits.todosPerEvent)")

        case .offDays:
            Image(systemName: limits.unlimitedOffDays
                  ? "checkmark.circle.fill"
                  : "minus.circle")
                .foregroundColor(limits.unlimitedOffDays ? .green : .gray)

        case .busyHours:
            Image(systemName: limits.unlimitedBusyHours
                  ? "checkmark.circle.fill"
                  : "minus.circle")
                .foregroundColor(limits.unlimitedBusyHours ? .green : .gray)

        case .sync:
            Image(systemName: limits.syncOnline
                  ? "checkmark.circle.fill"
                  : "minus.circle")
                .foregroundColor(limits.syncOnline ? .green : .gray)
        }
    }


}

enum PlanType: String, CaseIterable {
    case premium = "Premium"
    case pro = "Pro"
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
    case .advanceDays: return "feature_advance_days"
    case .members: return "feature_members"
    case .chat: return "feature_chat"
    case .todo: return "feature_todo"
    case .offDays: return "feature_off_days"
    case .busyHours: return "feature_busy_hours"
    case .sync: return "feature_sync"
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
        chatPerEvent: nil,   // ← unlimited
        todosPerEvent: 50,
        unlimitedOffDays: true,
        unlimitedBusyHours: true,
        syncOnline: true
    )
]
