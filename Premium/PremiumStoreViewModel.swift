//
// PremiumStoreViewModel.swift
//
// Since 2.5 every feature is free: everyone gets what Premium used to include,
// paid for by ads. On sale: a one-time "Remove Ads", and the Pro subscription
// (higher limits, no ads while active). Premium / Pro bought before 2.5 keeps
// the app ad-free for good.
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
    /// Effective plan for limits. `.premium` for everyone; `.pro` while a Pro subscription is active.
    @Published var tier: PremiumTier = .premium
    @Published var isLoaded: Bool = false
    /// No ads: ad-free for good, or a subscription is active. Starts from the last
    /// known value so ads never flash at launch.
    @Published private(set) var isAdFree: Bool = UserDefaults.standard.bool(forKey: adFreeKey)
    /// Bought Remove Ads, or Premium / Pro before 2.5 — Remove Ads has nothing left to offer.
    @Published private(set) var isLifetimeAdFree = false
    /// A Premium / Pro subscription is renewing (Settings offers to manage it).
    @Published private(set) var hasActiveSubscription = false
    /// Premium is free for everyone now — Settings tells these subscribers they can cancel.
    @Published private(set) var hasActivePremiumSubscription = false

    // Legacy – KHÔNG LƯU STATE
    var isPremium: Bool {
        tier >= .premium
    }

    var isPro: Bool {
        tier == .pro
    }

    var removeAdsProduct: Product? {
        products.first { $0.id == PremiumStore.removeAdsProductID }
    }

    /// Pro monthly + yearly.
    var proProducts: [Product] {
        products.filter { $0.id.contains(".pro.") }
    }

    @Published var loading: Bool = false

    private static let adFreeKey = "premium.isAdFree"

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
        // Pro limits while the subscription runs; everyone else gets Premium.
        entitlements.contains(where: { $0.contains(".pro.") }) ? .pro : .premium
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
        loading = true

        products = await PremiumStore.shared.getProducts()
        let entitlements = await PremiumStore.shared.getPurchasedIDs()

        tier = resolveTier(from: entitlements)
        hasActiveSubscription = entitlements.contains { $0 != PremiumStore.removeAdsProductID }
        hasActivePremiumSubscription = entitlements.contains { $0.contains(".premium.") }
        isLifetimeAdFree = await PremiumStore.shared.hasLifetimeAdFree()

        isAdFree = isLifetimeAdFree || hasActiveSubscription
        UserDefaults.standard.set(isAdFree, forKey: Self.adFreeKey)

        isLoaded = true          // ⭐ DÒNG QUAN TRỌNG NHẤT

        syncPremiumStatusToFirestoreIfNeeded()

        loading = false
    }

    // MARK: - SYNC TO FIRESTORE
    //
    // Other users' apps and the web booking page read `tier` from publicCalendar
    // to know how far ahead this calendar can be booked.

    private func syncPremiumStatusToFirestoreIfNeeded() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let key = "premium.syncedTier.\(uid)"
        guard UserDefaults.standard.string(forKey: key) != tier.firestoreValue else { return }

        let data: [String: Any] = [
            "tier": tier.firestoreValue,
            "isPremium": isPremium,
            "updatedAt": Timestamp(date: Date())
        ]

        let db = Firestore.firestore()

        db.collection("premiumStatus")
            .document(uid)
            .setData(data, merge: true)

        db.collection("publicCalendar")
            .document(uid)
            .setData(data, merge: true)

        UserDefaults.standard.set(tier.firestoreValue, forKey: key)
    }

    // MARK: - BUY
    func buy(_ product: Product) async -> Bool {
        let success = await PremiumStore.shared.purchase(product)
        await refresh()
        return success
    }

    // MARK: - RESTORE
    /// True when any purchase (Remove Ads, an active or pre-2.5 subscription) was found.
    func restore() async -> Bool {
        let found = await PremiumStore.shared.restore()
        await refresh()
        return found
    }
}


enum PremiumTier: Int, Comparable, Codable {
    case free = 0
    case premium = 1
    case pro = 2

    static func < (lhs: PremiumTier, rhs: PremiumTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Value stored in premiumStatus / publicCalendar `tier`.
    var firestoreValue: String {
        switch self {
        case .free: return "free"
        case .premium: return "premium"
        case .pro: return "pro"
        }
    }
}
struct PremiumLimits {
    let maxEventsPerDay: Int
    let maxBookingDaysAhead: Int
    let maxChatMessagesPerEvent: Int
    let maxTodosPerEvent: Int

    static func limits(for tier: PremiumTier) -> PremiumLimits {
        switch tier {
        // `.free` only still shows up for calendars whose owner runs an app older
        // than 2.5 — they get the same (free-for-everyone) limits.
        case .free, .premium:
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
