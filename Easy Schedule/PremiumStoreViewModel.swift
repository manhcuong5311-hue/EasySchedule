//
// PremiumStoreViewModel.swift
//

import SwiftUI
import StoreKit
import Combine

@MainActor
final class PremiumStoreViewModel: ObservableObject {

    static let shared = PremiumStoreViewModel()

    @Published var products: [Product] = []
    @Published var isPremium: Bool = false
    @Published var loading: Bool = false

    private init() {
        NotificationCenter.default.addObserver(
            forName: .PremiumStoreDidUpdate,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { await self?.refresh() }
        }

        Task { await refresh() }
    }

    // MARK: - START
    func start() {
        Task {
            loading = true
            await PremiumStore.shared.start()
            await refresh()
            loading = false
        }
    }

    // MARK: - REFRESH (lấy dữ liệu từ actor PremiumStore)
    func refresh() async {
        products = await PremiumStore.shared.getProducts()
        let purchased = await PremiumStore.shared.getPurchasedIDs()
        isPremium = !purchased.isEmpty
    }

    // MARK: - BUY
    func buy(_ product: Product) async -> Bool {
        let success = await PremiumStore.shared.purchase(product)
        await refresh()
        return success
    }

    // MARK: - RESTORE
    func restore() async -> Bool {
        let success = await PremiumStore.shared.restore()
        await refresh()
        return success
    }
}
