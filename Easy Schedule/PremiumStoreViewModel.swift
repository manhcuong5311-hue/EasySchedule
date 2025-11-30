//
//  PremiumStoreViewModel.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 30/11/25.
//

import Foundation
import StoreKit
import Combine

@MainActor
final class PremiumStoreViewModel: ObservableObject {

    static let shared = PremiumStoreViewModel()

    @Published var isPremium: Bool = false
    @Published var products: [Product] = []
    @Published var loading: Bool = false

    private init() {
        NotificationCenter.default.addObserver(
            forName: .PremiumStoreDidUpdate,
            object: nil,
            queue: .main
        ) { _ in
            Task { await self.refresh() }
        }
    }

    func start() {
        Task {
            loading = true
            await PremiumStore.shared.loadProducts()
            await refresh()
            loading = false
        }
    }

    func refresh() async {
        // cập nhật entitlement
        await PremiumStore.shared.refreshPurchased()

        // lấy products từ actor PremiumStore
        self.products = await PremiumStore.shared.getProducts()

        // lấy purchased IDs
        let ids = await PremiumStore.shared.getPurchasedProductIDs()

        // user có premium nếu purchased IDs không rỗng
        isPremium = !ids.isEmpty
    }

    func buy(_ product: Product) async -> Bool {
        let result = await PremiumStore.shared.purchase(product)
        return (try? result.get()) != nil
    }

    func restore() async -> Bool {
        let result = await PremiumStore.shared.restorePurchases()
        return (try? result.get()) != nil
    }
}
