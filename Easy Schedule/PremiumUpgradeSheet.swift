//
// PremiumUpgradeSheet.swift
//

import SwiftUI
import StoreKit

struct PremiumUpgradeSheet: View {

    @EnvironmentObject var premiumManager: PremiumManager
    @Environment(\.dismiss) var dismiss

    @State private var purchaseError: String? = nil
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {

                    // Header
                    VStack(spacing: 6) {
                        Text("Nâng cấp tài khoản")
                            .font(.title.bold())

                        if premiumManager.isPremiumUser {
                            Label("Bạn đang dùng bản Premium", systemImage: "star.fill")
                                .foregroundColor(.yellow)
                                .font(.headline)
                        } else {
                            Text("Mở khoá tất cả tính năng\nDung lượng & thời gian không giới hạn")
                                .multilineTextAlignment(.center)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.top, 16)

                    // MARK: - Product List
                    Group {
                        if premiumManager.products.isEmpty {
                            ProgressView("Đang tải gói…")
                                .padding(.vertical, 40)
                                .task { await premiumManager.loadProducts() }
                        } else {
                            VStack(spacing: 14) {
                                ForEach(premiumManager.products, id: \.id) { product in
                                    premiumCard(for: product)
                                }
                            }
                        }
                    }

                    Divider().padding(.vertical, 12)

                    // MARK: - Restore + Dev Mode
                    VStack(spacing: 12) {

                        Button {
                            Task {
                                isLoading = true
                                let ok = await premiumManager.restore()
                                isLoading = false
                                if ok { dismiss() }
                                else { purchaseError = "Không tìm thấy giao dịch cần khôi phục." }
                            }
                        } label: {
                            Text("Khôi phục mua hàng")
                                .font(.body)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isLoading)

                        #if DEBUG
                        Toggle("Fake Premium (Developer Mode)", isOn: $premiumManager.isFakePremium)
                            .padding(.horizontal)
                        #endif
                    }

                    Spacer().frame(height: 30)

                    Button("Đóng") { dismiss() }
                        .foregroundColor(.secondary)

                }
                .padding(.horizontal)
            }
            .alert("Lỗi mua hàng", isPresented: Binding(
                get: { purchaseError != nil },
                set: { _ in purchaseError = nil }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(purchaseError ?? "")
            }
        }
    }

    // MARK: - Premium Card
    private func premiumCard(for product: Product) -> some View {

        Button {
            Task {
                isLoading = true
                let success = await premiumManager.purchase(product)
                isLoading = false

                if success { dismiss() }
                else { purchaseError = "Thanh toán thất bại. Vui lòng thử lại." }
            }
        } label: {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(product.displayName)
                        .font(.headline)

                    Text(product.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text(product.displayPrice)
                    .font(.headline)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
            .cornerRadius(18)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.gray.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .opacity(isLoading ? 0.5 : 1)
    }
}
