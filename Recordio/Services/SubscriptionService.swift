import Foundation
import StoreKit
import Combine

@MainActor
class SubscriptionService: ObservableObject {
    static let shared = SubscriptionService()
    
    @Published var currentSubscription: SubscriptionTier = .free
    @Published var isSubscribed = false
    @Published var isLoading = false
    @Published var products: [Product] = []
    @Published var purchaseError: String?
    
    private var updateListenerTask: Task<Void, Error>?
    private var purchasedProductIDs = Set<String>()
    
    private init() {
        Task {
            await initializeStore()
        }
    }
    
    private func initializeStore() async {
        isLoading = true
        
        do {
            updateListenerTask = listenForTransactions()
            
            let storeProducts = try await Product.products(for: productIdentifiers)
            
            await MainActor.run {
                self.products = storeProducts.sorted(by: { $0.price < $1.price })
                self.isLoading = false
            }
            
            await updateSubscriptionStatus()
        } catch {
            await MainActor.run {
                self.purchaseError = error.localizedDescription
                self.isLoading = false
            }
        }
    }
    
    private var productIdentifiers: [String] {
        [
            "com.recordio.speaker.monthly",
            "com.recordio.speaker.yearly",
            "com.recordio.pro.monthly",
            "com.recordio.pro.yearly",
            "com.recordio.lifetime"
        ]
    }
    
    private func listenForTransactions() -> Task<Void, Error> {
        return Task.detached {
            for await result in Transaction.updates {
                do {
                    let transaction = try self.checkVerified(result)
                    
                    await self.updateSubscriptionStatus()
                    await transaction.finish()
                } catch {
                    print("Transaction verification failed: \(error)")
                }
            }
        }
    }
    
    private func updateSubscriptionStatus() async {
        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try self.checkVerified(result)
                let productID = transaction.productID
                
                await MainActor.run {
                    if productID.contains("speaker") {
                        self.currentSubscription = .speaker
                        self.isSubscribed = true
                    } else if productID.contains("pro") {
                        self.currentSubscription = .pro
                        self.isSubscribed = true
                    }
                    self.purchasedProductIDs.insert(productID)
                }
            } catch {
                print("Entitlement verification failed: \(error)")
            }
        }
        
        if purchasedProductIDs.isEmpty {
            await MainActor.run {
                self.currentSubscription = .free
                self.isSubscribed = false
            }
        }
    }
    
    func purchase(_ product: Product) async throws {
        isLoading = true
        
        AppLogger.shared.logEvent(AppLogger.Events.purchaseAttempt, parameters: [
            AppLogger.Params.productID: product.id
        ])
        
        do {
            let result = try await product.purchase()
            
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                
                await updateSubscriptionStatus()
                await transaction.finish()
                
                AppLogger.shared.logEvent(AppLogger.Events.purchaseSuccess, parameters: [
                    AppLogger.Params.productID: product.id
                ])
                
                await MainActor.run {
                    self.isLoading = false
                    self.purchaseError = nil
                }
                
            case .userCancelled:
                AppLogger.shared.logEvent(AppLogger.Events.purchaseFailed, parameters: [
                    AppLogger.Params.productID: product.id,
                    AppLogger.Params.errorDescription: "user_cancelled"
                ])
                await MainActor.run {
                    self.isLoading = false
                    self.purchaseError = nil
                }
                
            case .pending:
                await MainActor.run {
                    self.isLoading = false
                    self.purchaseError = "Purchase is pending. Please check your payment method."
                }
                
            @unknown default:
                AppLogger.shared.logEvent(AppLogger.Events.purchaseFailed, parameters: [
                    AppLogger.Params.productID: product.id,
                    AppLogger.Params.errorDescription: "unknown_error"
                ])
                await MainActor.run {
                    self.isLoading = false
                    self.purchaseError = "Purchase failed. Please try again."
                }
            }
        } catch {
            AppLogger.shared.logEvent(AppLogger.Events.purchaseFailed, parameters: [
                AppLogger.Params.productID: product.id,
                AppLogger.Params.errorDescription: error.localizedDescription
            ])
            AppLogger.shared.logError(error, additionalInfo: ["context": "purchase", "productID": product.id])
            
            await MainActor.run {
                self.isLoading = false
                self.purchaseError = error.localizedDescription
            }
            throw error
        }
    }
    
    func restorePurchases() async {
        isLoading = true
        
        do {
            try await AppStore.sync()
            await updateSubscriptionStatus()
            
            await MainActor.run {
                self.isLoading = false
                self.purchaseError = nil
            }
        } catch {
            await MainActor.run {
                self.isLoading = false
                self.purchaseError = error.localizedDescription
            }
        }
    }
    
    func checkEntitlement(for tier: SubscriptionTier) -> Bool {
        switch tier {
        case .free:
            return true
        case .speaker:
            return currentSubscription == .speaker || currentSubscription == .pro || currentSubscription == .lifetime
        case .pro:
            return currentSubscription == .pro || currentSubscription == .lifetime
        case .lifetime:
            return currentSubscription == .lifetime
        }
    }
    
    private nonisolated func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let safe):
            return safe
        case .unverified:
            throw TransactionError.failedVerification
        }
    }
}

enum TransactionError: Error, LocalizedError {
    case failedVerification
    
    var errorDescription: String? {
        switch self {
        case .failedVerification:
            return "Transaction verification failed"
        }
    }
}

extension SubscriptionService {
    func product(for tier: SubscriptionTier, period: SubscriptionPeriod) -> Product? {
        let productID = productIdentifier(for: tier, period: period)
        return products.first { $0.id == productID }
    }
    
    private func productIdentifier(for tier: SubscriptionTier, period: SubscriptionPeriod) -> String {
        switch tier {
        case .speaker:
            return period == .monthly ? "com.recordio.speaker.monthly" : "com.recordio.speaker.yearly"
        case .pro:
            return period == .monthly ? "com.recordio.pro.monthly" : "com.recordio.pro.yearly"
        case .lifetime:
            return "com.recordio.lifetime"
        case .free:
            return ""
        }
    }
}

enum SubscriptionPeriod {
    case monthly
    case yearly
}
