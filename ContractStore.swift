import Foundation
import Combine

final class ContractStore: ObservableObject {
    @Published var contracts: [Contract] = [] {
        didSet {
            saveContracts()
        }
    }

    private let persistenceKey = "savedContracts"
    private let persistsData: Bool

    init(persisted: Bool = true) {
        persistsData = persisted
        guard persisted,
              let data = UserDefaults.standard.data(forKey: persistenceKey),
              let savedContracts = try? JSONDecoder().decode([Contract].self, from: data) else {
            return
        }

        contracts = savedContracts
        Task { @MainActor in
            savedContracts
                .filter { $0.status != "Résilié" }
                .forEach { NotificationManager.shared.scheduleNotification(for: $0) }
        }
    }

    private func saveContracts() {
        guard persistsData,
              let data = try? JSONEncoder().encode(contracts) else { return }
        UserDefaults.standard.set(data, forKey: persistenceKey)
    }

    func add(_ contract: Contract) {
        contracts.append(contract)
        Task { @MainActor in NotificationManager.shared.scheduleNotification(for: contract) }
    }

    func update(_ contract: Contract) {
        guard let index = contracts.firstIndex(where: { $0.id == contract.id }) else { return }
        contracts[index] = contract
        Task { @MainActor in NotificationManager.shared.scheduleNotification(for: contract) }
    }

    func delete(at offsets: IndexSet, from displayedContracts: [Contract]) {
        let contractsToDelete = offsets.compactMap { index in
            displayedContracts.indices.contains(index) ? displayedContracts[index] : nil
        }
        contractsToDelete.forEach { contract in
            Task { @MainActor in NotificationManager.shared.cancelNotification(for: contract) }
        }
        let ids = Set(contractsToDelete.map(\.id))
        contracts.removeAll { ids.contains($0.id) }
    }
}
