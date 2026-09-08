//
//  PreviewData.swift
//  SuiviContrats
//
//  Created by erwan mahe on 08/09/2026.
//

import Foundation

enum PreviewData {
    static var contractStore: ContractStore {
        let store = ContractStore()
        let calendar = Calendar.current
        let today = Date()

        func date(monthOffset: Int) -> Date {
            calendar.date(byAdding: .month, value: monthOffset, to: today) ?? today
        }

        var assurance = Contract()
        assurance.name = "Assurance habitation"
        assurance.category = "Assurance"
        assurance.provider = "MAIF"
        assurance.anniversaryDate = date(monthOffset: 1)
        assurance.cancellationNoticeMonths = 2
        assurance.amountType = .annual
        assurance.amount = 480
        assurance.annualAmounts = [450, 480]
        assurance.status = "Actif"

        var assurance1 = Contract()
        assurance1.name = "Assurance1 habitation"
        assurance1.category = "Assurance"
        assurance1.provider = "AXA"
        assurance1.anniversaryDate = date(monthOffset: 1)
        assurance1.cancellationNoticeMonths = 1
        assurance1.amountType = .annual
        assurance1.amount = 510
        assurance1.status = "Résilié"

        var internet = Contract()
        internet.name = "Fibre Internet"
        internet.category = "Abonnement Internet"
        internet.provider = "Orange"
        internet.anniversaryDate = date(monthOffset: 3)
        internet.cancellationNoticeMonths = 1
        internet.amountType = .monthly
        internet.amount = 39.99
        internet.status = "Reconduit"

        var musique = Contract()
        musique.name = "Abonnement musique"
        musique.category = "Abonnement Musique"
        musique.provider = "Deezer"
        musique.anniversaryDate = date(monthOffset: 6)
        musique.amountType = .monthly
        musique.amount = 11.99
        musique.status = "Actif"

        store.contracts = [
            assurance,
            assurance1,
            internet,
            musique
        ]

        return store
    }
}
