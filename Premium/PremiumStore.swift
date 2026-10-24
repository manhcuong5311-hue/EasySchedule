//
// PremiumStore.swift
//

import Foundation
import StoreKit

extension Notification.Name {
    static let PremiumStoreDidUpdate = Notification.Name("PremiumStore.DidUpdate")
}

actor PremiumStore {

    // MARK: - Singleton
    static let shared = PremiumStore()

    // MARK: - Product IDs
    /// One-time purchase that turns ads off for good.
    static let removeAdsProductID = "com.SamCorp.EasySchedule.removeads"

    private let productIDs: Set<String> = [
        removeAdsProductID,

        // PRO — still sold: higher limits, no ads while active
        "com.SamCorp.EasySchedule.pro.monthly",
        "com.SamCorp.EasySchedule.pro.yearly",

        // PREMIUM — no longer sold (every feature is free); kept so existing
        // subscribers are still recognised and restore keeps working.
        "com.SamCorp.EasySchedule.premium.monthly",
        "com.SamCorp.EasySchedule.premium.yearly"
    ]

    /// Premium / Pro bought before every feature went free keeps the app ad-free
    /// for good. Subscriptions bought later only remove ads while they're active.
    private static let freeSwitchDate = ISO8601DateFormatter().date(from: "2026-10-24T00:00:00+07:00")!

    // MARK: - Stored properties
    private var products: [Product] = []
    private var purchasedProductIDs: Set<String> = []
    /// Remove Ads, or a Premium / Pro plan bought before `freeSwitchDate` (even if expired).
    private var lifetimeAdFree = false
    // MARK: - Init
    init() {
        if #available(iOS 15.0, *) {
            Task {
                await updateEntitlements()
                // The view model may have refreshed before this finished.
                await self.notifyUpdate()
                await self.listenForTransactions() }
        }
    }

    // MARK: - Public getters
    func getProducts() -> [Product] {
        products
    }

    func getPurchasedIDs() -> Set<String> {
        purchasedProductIDs
    }

    func hasLifetimeAdFree() -> Bool {
        lifetimeAdFree
    }

    // MARK: - Load Products
    func start() async {
        guard #available(iOS 15.0, *) else { return }

        do {
            let fetched = try await Product.products(for: Array(productIDs))
            products = fetched.sorted { $0.displayName < $1.displayName }

            await updateEntitlements()
            notifyUpdate()

        } catch {
            print("❌ Failed to load products:", error.localizedDescription)
        }
    }

    // MARK: - Purchase
    func purchase(_ product: Product) async -> Bool {
       
        guard #available(iOS 15.0, *) else { return false }

        // 🔥 FIX 1 — Ensure products loaded before purchase
        if products.isEmpty {
            print("⚠️ Products empty — auto-calling start() before purchase")
            await start()
        }

        do {
            // 🔥 FIX 2 — Add timeout so UI does not spin forever
            let result = try await withTimeout(seconds: 15) {
                try await product.purchase()
            }

            switch result {

            case .success(let verification):
                let transaction = try checkVerified(verification)
                await markPurchased(transaction.productID)
                await transaction.finish()
                notifyUpdate()
                return true

            case .pending:
                return false

            case .userCancelled:
                return false

            @unknown default:
                return false
            }

        } catch {
            print("❌ Purchase failed:", error.localizedDescription)
            return false
        }
    }

    // MARK: - Timeout wrapper
    private func withTimeout<T>(seconds: Double,
                                operation: @escaping () async throws -> T) async throws -> T {

        try await withThrowingTaskGroup(of: T.self) { group in

            group.addTask {
                return try await operation()
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw PremiumError.timeout
            }

            let value = try await group.next()!
            group.cancelAll()
            return value
        }
    }

    // MARK: - Restore
    /// Re-syncs with the App Store. Returns true when any purchase was found.
    func restore() async -> Bool {
        guard #available(iOS 15.0, *) else { return false }

        do {
            try await AppStore.sync()
        } catch {
            print("❌ Restore failed:", error.localizedDescription)
        }

        await updateEntitlements()
        notifyUpdate()
        return lifetimeAdFree || !purchasedProductIDs.isEmpty
    }

    // MARK: - Listen for updates
    @available(iOS 15.0, *)
    private func listenForTransactions() async {
        for await update in Transaction.updates {
            do {
                let transaction = try checkVerified(update)
                await markPurchased(transaction.productID)
                await transaction.finish()
                notifyUpdate()

            } catch {
                print("❌ Transaction update verification failed:", error.localizedDescription)
            }
        }
    }

    // MARK: - Entitlement sync
    @available(iOS 15.0, *)
    private func updateEntitlements() async {
        purchasedProductIDs.removeAll()

        for await entitlement in Transaction.currentEntitlements {
            do {
                let transaction = try checkVerified(entitlement)
                purchasedProductIDs.insert(transaction.productID)
            } catch {}
        }

        // Expired legacy subscriptions are no longer entitlements but still count.
        var adFreeForGood = false
        for await result in Transaction.all {
            if let transaction = try? checkVerified(result),
               transaction.revocationDate == nil,
               transaction.productID == Self.removeAdsProductID
                || transaction.originalPurchaseDate < Self.freeSwitchDate {
                adFreeForGood = true
                break
            }
        }
        lifetimeAdFree = adFreeForGood
    }
    private func markPurchased(_ id: String) async {
        purchasedProductIDs.insert(id)
        if id == Self.removeAdsProductID {
            lifetimeAdFree = true
        }
    }

    // MARK: - Verification fix (IMPORTANT FOR APP REVIEW)
    @available(iOS 15.0, *)
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let safe):
            return safe

        case .unverified(_, let error):
            // Không accept unverified ở bất kỳ môi trường nào
            print("⚠️ Unverified transaction:", error.localizedDescription)
            throw PremiumError.unverified
        }
    }
    // MARK: - Mark purchased
    private func notifyUpdate() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .PremiumStoreDidUpdate, object: nil)
        }
    }

    // MARK: - Error Types
    enum PremiumError: LocalizedError {
        case unverified
        case timeout

        var errorDescription: String? {
            switch self {
            case .unverified:
                return String(localized: "premium_error_unverified")
            case .timeout:
                return String(localized: "premium_error_timeout")
            }
        }
    }

}
