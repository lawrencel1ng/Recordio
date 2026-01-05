import Foundation

enum SubscriptionTier: String, Codable, CaseIterable {
    case free = "free"
    case speaker = "speaker"
    case pro = "pro"
    case lifetime = "lifetime"
    
    var displayName: String {
        switch self {
        case .free: return "Free"
        case .speaker: return "Speaker"
        case .pro: return "Pro"
        case .lifetime: return "Lifetime"
        }
    }
    
    var monthlyPrice: Double? {
        switch self {
        case .free: return 0
        case .speaker: return 2.99
        case .pro: return 4.99
        case .lifetime: return nil
        }
    }
    
    var lifetimePrice: Double? {
        switch self {
        case .lifetime: return 79.99
        default: return nil
        }
    }
    
    var formattedMonthlyPrice: String {
        guard let price = monthlyPrice else { return "N/A" }
        if price == 0 { return "Free" }
        return String(format: "$%.2f", price)
    }
    
    var formattedLifetimePrice: String {
        guard let price = lifetimePrice else { return "N/A" }
        return String(format: "$%.2f", price)
    }
    
    var features: [String] {
        switch self {
        case .free:
            return [
                "Unlimited recording",
                "Basic audio quality",
                "Local storage only"
            ]
        case .speaker:
            return [
                "Everything in Free",
                "Speaker identification",
                "Color-coded speakers",
                "Speaker statistics"
            ]
        case .pro:
            return [
                "Everything in Speaker",
                "AI noise reduction",
                "AI summaries",
                "Advanced audio enhancement",
                "Export individual speaker tracks"
            ]
        case .lifetime:
            return [
                "Everything in Pro",
                "One-time payment",
                "All future features",
                "Priority support"
            ]
        }
    }
}
