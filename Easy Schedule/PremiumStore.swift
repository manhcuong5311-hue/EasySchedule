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
    private let productIDs: Set<String> = [
        "com.SamCorp.EasySchedule.premium.monthly",
        "com.SamCorp.EasySchedule.premium.yearly"
    ]

    // MARK: - Stored properties
    private var products: [Product] = []
    private var purchasedProductIDs: Set<String> = []

    // Optional fake premium (for dev mode)
    private let fakePremiumKey = "PremiumStore_FakePremiumEnabled"
    var isFakePremiumEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: fakePremiumKey) }
        set { UserDefaults.standard.set(newValue, forKey: fakePremiumKey) }
    }

    // MARK: - Init
    init() {
        if #available(iOS 15.0, *) {
            Task {
                await updateEntitlements()
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
        if isFakePremiumEnabled {
            await markPurchased(product.id)
            notifyUpdate()
            return true
        }

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
    func restore() async -> Bool {
        purchasedProductIDs.removeAll()
        if isFakePremiumEnabled {
            for id in productIDs { await markPurchased(id) }
            notifyUpdate()
            return true
        }

        guard #available(iOS 15.0, *) else { return false }

        do {
            for await entitlement in Transaction.currentEntitlements {
                let verified = try checkVerified(entitlement)
                await markPurchased(verified.productID)
            }
            notifyUpdate()
            return true

        } catch {
            print("❌ Restore failed:", error.localizedDescription)
            return false
        }
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
                await transaction.finish()
            } catch {}
        }
    }
    private func markPurchased(_ id: String) async {
        purchasedProductIDs.insert(id)
    }
    private var isSandbox: Bool {
        return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
    }

    // MARK: - Verification fix (IMPORTANT FOR APP REVIEW)
    @available(iOS 15.0, *)
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let safe):
            return safe

        case .unverified(let unsafe, _):
            if isSandbox {
                // Cho phép sandbox để Apple review được
                print("⚠️ Accepting unverified transaction in SANDBOX")
                return unsafe
            }
            // Production: không cho phép → đúng chuẩn bảo mật
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
