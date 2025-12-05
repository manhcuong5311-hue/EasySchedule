import Foundation
import StoreKit

extension Notification.Name {
    static let PremiumStoreDidUpdate = Notification.Name("PremiumStore.DidUpdatePurchaseStatus")
}

actor PremiumStore {
    static let shared = PremiumStore()

    private let productIdentifiers: Set<String> = [
        "com.SamCorp.EasySchedule.premium.monthly",
           "com.SamCorp.EasySchedule.premium.yearly"
           
    ]

    private var productsInternal: [Product] = []
    private var purchasedIDsInternal: Set<String> = []

    private let fakePremiumKey = "PremiumStore_FakePremiumEnabled"
    var isFakePremiumEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: fakePremiumKey) }
        set { UserDefaults.standard.set(newValue, forKey: fakePremiumKey) }
    }

    // ========= PUBLIC GETTERS (ViewModel gọi) =========
    func getProducts() -> [Product] {
        return productsInternal
    }

    func getPurchasedProductIDs() -> Set<String> {
        return purchasedIDsInternal
    }

    func refreshPurchased() async {
        if #available(iOS 15.0, *) {
            await updatePurchasedProducts()
            notifyUpdate()
        }
    }

    // ========= LOAD PRODUCTS =========
    func loadProducts() async {
        if #available(iOS 15.0, *) {
            do {
                let fetched = try await Product.products(for: Array(productIdentifiers))
                productsInternal = fetched.sorted { $0.displayName < $1.displayName }
                await updatePurchasedProducts()
                notifyUpdate()
            } catch {
                print("PremiumStore: failed:", error.localizedDescription)
            }
        }
    }

    // ========= BUY =========
    func purchase(_ product: Product) async -> Result<Transaction?, Error> {
        if isFakePremiumEnabled {
            await markPurchased(product.id)
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
                    await markPurchased(transaction.productID)
                    notifyUpdate()
                    return .success(transaction)

                case .userCancelled:
                    return .failure(PremiumError.userCancelled)

                case .pending:
                    return .failure(PremiumError.pending)

                @unknown default:
                    return .failure(PremiumError.unknown)
                }

            } catch {
                return .failure(error)
            }
        }

        return .failure(PremiumError.storeUnavailable)
    }

    // ========= RESTORE =========
    func restorePurchases() async -> Result<Void, Error> {
        if isFakePremiumEnabled {
            for id in productIdentifiers { await markPurchased(id) }
            notifyUpdate()
            return .success(())
        }

        if #available(iOS 15.0, *) {
            do {
                for await v in Transaction.currentEntitlements {
                    let t = try checkVerified(v)
                    await markPurchased(t.productID)
                }
                notifyUpdate()
                return .success(())
            } catch {
                return .failure(error)
            }
        }
        return .failure(PremiumError.storeUnavailable)
    }

    // ========= INTERNAL ENTITLEMENT SYNC =========
    @available(iOS 15.0, *)
    private func updatePurchasedProducts() async {
        purchasedIDsInternal.removeAll()
        for await v in Transaction.currentEntitlements {
            do {
                let t = try checkVerified(v)
                purchasedIDsInternal.insert(t.productID)
            } catch {}
        }
    }

    // ========= HELPERS =========
    @available(iOS 15.0, *)
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let safe): return safe
        case .unverified: throw PremiumError.unverifiedTransaction
        }
    }

    @available(iOS 15.0, *)
    private func markPurchased(_ id: String) async {
        purchasedIDsInternal.insert(id)
        var stored = UserDefaults.standard.stringArray(forKey: "PremiumStore_purchased") ?? []
        if !stored.contains(id) {
            stored.append(id)
            UserDefaults.standard.set(stored, forKey: "PremiumStore_purchased")
        }
    }

    private func notifyUpdate() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .PremiumStoreDidUpdate, object: nil)
        }
    }

    enum PremiumError: LocalizedError {
        case storeUnavailable, userCancelled, pending, unknown, unverifiedTransaction
    }
}
