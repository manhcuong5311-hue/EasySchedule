//
//  PremiumStore.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 22/11/25.
//

// PremiumStore.swift
// Easy Schedule — StoreKit helper (StoreKit 2 with fallback)
import Foundation
import StoreKit

/// Notification posted when purchase status or products list changes
extension Notification.Name {
    static let PremiumStoreDidUpdate = Notification.Name("PremiumStore.DidUpdatePurchaseStatus")
}

actor PremiumStore {
    static let shared = PremiumStore()

    /// Put your product ids here (match App Store Connect)
    private let productIdentifiers: Set<String> = [
        "com.yourcompany.easyschedule.premium.monthly",
        "com.yourcompany.easyschedule.premium.yearly",
        "com.yourcompany.easyschedule.premium.lifetime"
    ]

    // In-memory cache
    private(set) var products: [Product] = []
    private(set) var purchasedProductIDs: Set<String> = []

    /// Fake/pseudo premium mode for local testing when App Store not available
    private let fakePremiumKey = "PremiumStore_FakePremiumEnabled"

    var isFakePremiumEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: fakePremiumKey) }
        set { UserDefaults.standard.set(newValue, forKey: fakePremiumKey) }
    }

    // MARK: - Public API

    /// Load products from App Store (async)
    func loadProducts() async {
        if #available(iOS 15.0, *) {
            do {
                let fetched = try await Product.products(for: Array(productIdentifiers))
                // sort stable
                self.products = fetched.sorted { $0.displayName < $1.displayName }
                // try restore/check existing transactions
                await updatePurchasedProducts()
                notifyUpdate()
            } catch {
                print("PremiumStore: failed to fetch products:", error.localizedDescription)
            }
        } else {
            // fallback: nothing we can do — maybe prefill UI with product ids
            print("PremiumStore: StoreKit2 not available on runtime — cannot fetch products")
        }
    }

    /// Purchase a product
    func purchase(_ product: Product) async -> Result<Transaction?, Error> {
        if isFakePremiumEnabled {
            await markProductAsPurchased(product.id)
            notifyUpdate()
            return .success(nil)
        }

        if #available(iOS 15.0, *) {
            do {
                let result = try await product.purchase()
                switch result {
                case .success(let verification):
                    let transaction = try checkVerified(verification)
                    await transaction.finish()
                    await markProductAsPurchased(transaction.productID)
                    notifyUpdate()
                    return .success(transaction)

                case .userCancelled:
                    return .failure(PremiumStoreError.userCancelled)

                case .pending:
                    return .failure(PremiumStoreError.pending)

                @unknown default:
                    return .failure(PremiumStoreError.unknown)
                }
            } catch {
                return .failure(error)
            }
        } else {
            return .failure(PremiumStoreError.storeUnavailable)
        }
    }


    /// Restore purchases (iOS triggers existing transactions)
    func restorePurchases() async -> Result<Void, Error> {
        if isFakePremiumEnabled {
            // simulate: mark all known product IDs purchased
            for id in productIdentifiers { await markProductAsPurchased(id) }
            notifyUpdate()
            return .success(())
        }
        if #available(iOS 15.0, *) {
            do {
                for await verification in Transaction.currentEntitlements {
                    let transaction = try checkVerified(verification)
                    await markProductAsPurchased(transaction.productID)
                }
                notifyUpdate()
                return .success(())
            } catch {
                return .failure(error)
            }
        } else {
            return .failure(PremiumStoreError.storeUnavailable)
        }
    }

    /// Check whether a product is purchased (or fake mode)
    func isPurchased(_ productId: String) -> Bool {
        if isFakePremiumEnabled { return true }
        return purchasedProductIDs.contains(productId)
    }

    // MARK: - Internal helpers

    @available(iOS 15.0, *)
    private func updatePurchasedProducts() async {
        purchasedProductIDs.removeAll()
        for await verification in Transaction.currentEntitlements {
            do {
                let t = try checkVerified(verification)
                purchasedProductIDs.insert(t.productID)
            } catch {
                // invalid transaction — ignore
            }
        }
    }

    private func notifyUpdate() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .PremiumStoreDidUpdate, object: nil)
        }
    }

    @available(iOS 15.0, *)
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw PremiumStoreError.unverifiedTransaction
        case .verified(let safe):
            return safe
        }
    }

    @available(iOS 15.0, *)
    private func markProductAsPurchased(_ productId: String) async {
        purchasedProductIDs.insert(productId)
        // optionally persist minimal state for quick check (note: real truth is transactions)
        var stored = UserDefaults.standard.stringArray(forKey: "PremiumStore_purchased") ?? []
        if !stored.contains(productId) {
            stored.append(productId)
            UserDefaults.standard.set(stored, forKey: "PremiumStore_purchased")
        }
    }

  

    // MARK: - Errors
    enum PremiumStoreError: LocalizedError {
        case storeUnavailable
        case userCancelled
        case pending
        case unknown
        case unverifiedTransaction

        var errorDescription: String? {
            switch self {
            case .storeUnavailable:
                return String(localized: "store_unavailable")
            case .userCancelled:
                return String(localized: "user_cancelled")
            case .pending:
                return String(localized: "purchase_pending")
            case .unknown:
                return String(localized: "purchase_unknown_error")
            case .unverifiedTransaction:
                return String(localized: "transaction_unverified")
            }
        }

    }
}
