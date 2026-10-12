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

struct ContractGroup: Identifiable, Codable, Equatable {
    var id = UUID()
    var name = ""
}

struct Contract: Identifiable, Codable, Equatable {
    var id = UUID()
    var name = ""
    var groupID: UUID?
    var category = "Assurance"
    var provider = ""
    var anniversaryDate = Date()
    var periodicityYears = 1
    var cancellationNoticeMonths = 1
    var amountType: AmountType = .annual
    var amount: Double = 0
    var annualAmounts: [Double] = []
    var status = "Actif"
    var comment = ""

    init() {}

    enum CodingKeys: String, CodingKey {
        case id, name, groupID, category, provider, anniversaryDate, periodicityYears
        case cancellationNoticeMonths, amountType, amount, annualAmounts, status, comment
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        groupID = try container.decodeIfPresent(UUID.self, forKey: .groupID)
        category = try container.decodeIfPresent(String.self, forKey: .category) ?? "Assurance"
        provider = try container.decodeIfPresent(String.self, forKey: .provider) ?? ""
        anniversaryDate = try container.decodeIfPresent(Date.self, forKey: .anniversaryDate) ?? Date()
        periodicityYears = max(1, try container.decodeIfPresent(Int.self, forKey: .periodicityYears) ?? 1)
        cancellationNoticeMonths = try container.decodeIfPresent(Int.self, forKey: .cancellationNoticeMonths) ?? 1
        amountType = try container.decodeIfPresent(AmountType.self, forKey: .amountType) ?? .annual
        annualAmounts = try container.decodeIfPresent([Double].self, forKey: .annualAmounts) ?? []
        amount = try container.decodeIfPresent(Double.self, forKey: .amount) ?? annualAmounts.last ?? 0
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "Actif"
        comment = try container.decodeIfPresent(String.self, forKey: .comment)
            ?? ""
    }

    func anniversaryDate(year: Int, calendar: Calendar = .current) -> Date {
        let components = DateComponents(
            year: year,
            month: calendar.component(.month, from: anniversaryDate),
            day: calendar.component(.day, from: anniversaryDate)
        )
        return calendar.date(from: components)
            ?? calendar.date(from: DateComponents(year: year, month: components.month, day: 28))
            ?? anniversaryDate
    }

    func nextAnniversary(after date: Date, calendar: Calendar = .current) -> Date {
        let baseYear = calendar.component(.year, from: anniversaryDate)
        let currentYear = calendar.component(.year, from: date)
        let period = max(periodicityYears, 1)
        var index = (currentYear - baseYear) / period
        if baseYear + index * period < currentYear { index += 1 }

        while true {
            let candidate = anniversaryDate(year: baseYear + index * period, calendar: calendar)
            if candidate > date { return candidate }
            index += 1
        }
    }

    func previousAnniversary(before date: Date, calendar: Calendar = .current) -> Date {
        let next = nextAnniversary(after: date, calendar: calendar)
        let period = max(periodicityYears, 1)
        return calendar.date(byAdding: .year, value: -period, to: next) ?? anniversaryDate
    }

    static let categories = [
        "Assurance", "Abonnement Internet", "Abonnement Musique", "Abonnement Télé", "Controle technique", "Énergie", "Papier identité", "Téléphonie", "Autre"
    ]
    static let statuses = ["Actif", "Reconduit", "Résilié"]
    static let noticeOptions = [0, 1, 2, 3, 6]
}
