//
// PremiumStoreViewModel.swift
//

import SwiftUI
import StoreKit
import Combine
import FirebaseFirestore
import FirebaseAuth

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

    // MARK: - REFRESH (nhận entitlement từ PremiumStore)
    func refresh() async {
        products = await PremiumStore.shared.getProducts()

        let old = isPremium
        let entitlements = await PremiumStore.shared.getPurchasedIDs()
        isPremium = !entitlements.isEmpty

        if old != isPremium {
            syncPremiumStatusToFirestore()
        }
    }


    // MARK: - SYNC TO FIRESTORE (A là người mua Premium)
    func syncPremiumStatusToFirestore() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let db = Firestore.firestore()

        let data: [String: Any] = [
            "isPremium": isPremium,
            "updatedAt": Timestamp(date: Date())
        ]

        db.collection("premiumStatus")
            .document(uid)
            .setData(data, merge: true)

        db.collection("publicCalendar")
            .document(uid)
            .setData(data, merge: true)
    }


    // MARK: - BUY
    func buy(_ product: Product) async -> Bool {
        let success = await PremiumStore.shared.purchase(product)
        await refresh()

        if success {
            syncPremiumStatusToFirestore()
        }

        return success
    }

    // MARK: - RESTORE
    func restore() async -> Bool {
        let success = await PremiumStore.shared.restore()
        await refresh()

        if success {
            syncPremiumStatusToFirestore()
        }

        return success
    }
}
