// PremiumUpgradeSheet.swift
//

import SwiftUI
import StoreKit

struct PremiumUpgradeSheet: View {

    @EnvironmentObject var premium: PremiumStoreViewModel
    @Environment(\.dismiss) var dismiss

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

                        Text(String(localized: "upgrade_premium_title"))
                            .font(.largeTitle.bold())
                            .multilineTextAlignment(.center)

                        Text(String(localized: "upgrade_premium_subtitle"))
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        if premium.isPremium {
                            Label(String(localized: "premium_activated"),
                                  systemImage: "star.fill")
                                .foregroundColor(.yellow)
                                .font(.headline)
                                .padding(.top, 4)
                        }
                    }
                    .padding(.top, 20)

                    // MARK: - Product Cards
                    if premium.products.isEmpty {
                        ProgressView(String(localized: "loading_packages"))
                            .padding(.vertical, 40)
                            .task { premium.start() }
                    } else {
                        VStack(spacing: 18) {
                            ForEach(premium.products, id: \.id) { product in
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
            .alert(
                String(localized: "purchase_error"),
                isPresented: Binding(
                    get: { purchaseError != nil },
                    set: { _ in purchaseError = nil }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(purchaseError ?? "")
            }
        }
    }

    // MARK: - Premium Card UI
    private func premiumCard(for product: Product) -> some View {

        Button {
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
                if product.id.contains("yearly") {
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
    }
}
