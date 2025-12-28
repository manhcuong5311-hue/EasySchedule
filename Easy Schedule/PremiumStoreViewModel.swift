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
    @Published var tier: PremiumTier = .free

    // Legacy – KHÔNG LƯU STATE
    var isPremium: Bool {
        tier >= .premium
    }

    var isPro: Bool {
        tier == .pro
    }


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
 
    var limits: PremiumLimits {
        PremiumLimits.limits(for: tier)
    }

    private func resolveTier(from entitlements: Set<String>) -> PremiumTier {

        // Ưu tiên Pro
        if entitlements.contains(where: { $0.contains("pro") }) {
            return .pro
        }

        // Premium thường
        if entitlements.contains(where: { $0.contains("premium") }) {
            return .premium
        }

        return .free
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

        let oldTier = tier
        let entitlements = await PremiumStore.shared.getPurchasedIDs()

        tier = resolveTier(from: entitlements)

        if oldTier != tier {
            syncPremiumStatusToFirestore()
        }
    }




    // MARK: - SYNC TO FIRESTORE (A là người mua Premium)
    func syncPremiumStatusToFirestore() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let db = Firestore.firestore()

        let data: [String: Any] = [
            "tier": tier == .free ? "free" : (tier == .premium ? "premium" : "pro"),
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


enum PremiumTier: Int, Comparable, Codable {
    case free = 0
    case premium = 1
    case pro = 2

    static func < (lhs: PremiumTier, rhs: PremiumTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
struct PremiumLimits {
    let maxEventsPerDay: Int
    let maxBookingDaysAhead: Int
    let maxChatMessagesPerEvent: Int
    let maxTodosPerEvent: Int

    static func limits(for tier: PremiumTier) -> PremiumLimits {
        switch tier {
        case .free:
            return .init(
                maxEventsPerDay: 2,
                maxBookingDaysAhead: 7,
                maxChatMessagesPerEvent: 100,
                maxTodosPerEvent: 5
            )

        case .premium:
            return .init(
                maxEventsPerDay: 20,
                maxBookingDaysAhead: 90,
                maxChatMessagesPerEvent: 500,
                maxTodosPerEvent: 20
            )

        case .pro:
            return .init(
                maxEventsPerDay: 50,
                maxBookingDaysAhead: 270,
                maxChatMessagesPerEvent: .max,
                maxTodosPerEvent: 50
            )
        }
    }
}
