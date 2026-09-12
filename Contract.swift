import Foundation

enum AmountType: String, Codable, CaseIterable {
    case annual
    case monthly

    var label: String {
        switch self {
        case .annual: return "Annuel"
        case .monthly: return "Mensuel"
        }
    }

    var unit: String {
        switch self {
        case .annual: return "€ / an"
        case .monthly: return "€ / mois"
        }
    }
}

struct Contract: Identifiable, Codable, Equatable {
    var id = UUID()
    var name = ""
    var category = "Assurance"
    var provider = ""
    var anniversaryDate = Date()
    var cancellationNoticeMonths = 1
    var amountType: AmountType = .annual
    var amount: Double = 0
    var annualAmounts: [Double] = []
    var status = "Actif"
    var comment = ""

    init() {}

    enum CodingKeys: String, CodingKey {
        case id, name, category, provider, anniversaryDate
        case cancellationNoticeMonths, amountType, amount, annualAmounts, status, comment
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        category = try container.decodeIfPresent(String.self, forKey: .category) ?? "Assurance"
        provider = try container.decodeIfPresent(String.self, forKey: .provider) ?? ""
        anniversaryDate = try container.decodeIfPresent(Date.self, forKey: .anniversaryDate) ?? Date()
        cancellationNoticeMonths = try container.decodeIfPresent(Int.self, forKey: .cancellationNoticeMonths) ?? 1
        amountType = try container.decodeIfPresent(AmountType.self, forKey: .amountType) ?? .annual
        annualAmounts = try container.decodeIfPresent([Double].self, forKey: .annualAmounts) ?? []
        amount = try container.decodeIfPresent(Double.self, forKey: .amount) ?? annualAmounts.last ?? 0
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "Actif"
        comment = try container.decodeIfPresent(String.self, forKey: .comment) ?? ""
    }

    static let categories = [
        "Assurance", "Abonnement Internet", "Abonnement Musique", "Abonnement Télé",
        "Papier identité", "Téléphonie", "Énergie", "Autre"
    ]
    static let statuses = ["Actif", "Reconduit", "Résilié"]
    static let noticeOptions = [0, 1, 2, 3, 6]
}
