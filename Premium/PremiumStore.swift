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
    /// One-time purchase that turns ads off. Since 2.5 it is the only product on sale.
    static let removeAdsProductID = "com.SamCorp.EasySchedule.removeads"

    private let productIDs: Set<String> = [
        removeAdsProductID,

        // Legacy subscriptions (no longer sold) — kept so existing subscribers
        // are still recognised and restore keeps working.
        "com.SamCorp.EasySchedule.premium.monthly",
        "com.SamCorp.EasySchedule.premium.yearly",
        "com.SamCorp.EasySchedule.pro.monthly",
        "com.SamCorp.EasySchedule.pro.yearly"
    ]

    // MARK: - Stored properties
    private var products: [Product] = []
    private var purchasedProductIDs: Set<String> = []
    /// Any purchase ever (Remove Ads, or a Premium / Pro subscription even if it
    /// has since expired) — those users never see ads.
    private var everPurchased = false
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

    func hasEverPurchased() -> Bool {
        everPurchased
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
        return everPurchased
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

        // Expired subscriptions are no longer entitlements but still count as a purchase.
        var purchasedBefore = !purchasedProductIDs.isEmpty
        if !purchasedBefore {
            for await result in Transaction.all {
                if let transaction = try? checkVerified(result),
                   transaction.revocationDate == nil {
                    purchasedBefore = true
                    break
                }
            }
        }
        everPurchased = purchasedBefore
    }
    private func markPurchased(_ id: String) async {
        purchasedProductIDs.insert(id)
        everPurchased = true
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
