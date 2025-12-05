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
            // Swift 6-safe: async call inside Task
            Task { await self.listenForTransactions() }
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

        do {
            let result = try await product.purchase()

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
            print("❌ Purchase failed:", error)
            return false
        }
    }

    // MARK: - Restore
    func restore() async -> Bool {
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
            print("❌ Restore failed:", error)
            return false
        }
    }

    // MARK: - Listen for updates (REQUIRED BY APP REVIEW)
    @available(iOS 15.0, *)
    private func listenForTransactions() async {
        for await update in Transaction.updates {
            do {
                let transaction = try checkVerified(update)
                await markPurchased(transaction.productID)
                await transaction.finish()
                notifyUpdate()

            } catch {
                print("❌ Transaction update verification failed:", error)
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
    }

    // MARK: - Helpers
    @available(iOS 15.0, *)
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let safe):
            safe
        case .unverified:
            throw PremiumError.unverified
        }
    }

    @available(iOS 15.0, *)
    private func markPurchased(_ id: String) async {
        purchasedProductIDs.insert(id)

        var saved = UserDefaults.standard.stringArray(forKey: "PremiumStore_purchased") ?? []
        if !saved.contains(id) {
            saved.append(id)
            UserDefaults.standard.set(saved, forKey: "PremiumStore_purchased")
        }
    }

    private func notifyUpdate() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .PremiumStoreDidUpdate, object: nil)
        }
    }

    // MARK: - Error Types
    enum PremiumError: LocalizedError {
        case unverified
    }
}
