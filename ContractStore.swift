import Foundation
import Combine

final class ContractStore: ObservableObject {
    @Published var contracts: [Contract] = [] {
        didSet {
            saveContracts()
        }
    }

    @Published var groups: [ContractGroup] = [] {
        didSet {
            saveGroups()
        }
    }

    private let persistenceKey = "savedContracts"
    private let groupsPersistenceKey = "savedContractGroups"
    private let persistsData: Bool

    init(persisted: Bool = true) {
        persistsData = persisted
        guard persisted else { return }

        if let data = UserDefaults.standard.data(forKey: persistenceKey),
           let savedContracts = try? JSONDecoder().decode([Contract].self, from: data) {
            contracts = savedContracts
            Task { @MainActor in
                savedContracts
                    .filter { $0.status != "Résilié" }
                    .forEach { NotificationManager.shared.scheduleNotification(for: $0) }
            }
        }

        if let data = UserDefaults.standard.data(forKey: groupsPersistenceKey),
           let savedGroups = try? JSONDecoder().decode([ContractGroup].self, from: data) {
            groups = savedGroups
        }
    }

    private func saveContracts() {
        guard persistsData,
              let data = try? JSONEncoder().encode(contracts) else { return }
        UserDefaults.standard.set(data, forKey: persistenceKey)
    }

    private func saveGroups() {
        guard persistsData,
              let data = try? JSONEncoder().encode(groups) else { return }
        UserDefaults.standard.set(data, forKey: groupsPersistenceKey)
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

    func addGroup(_ group: ContractGroup) {
        groups.append(group)
    }

    func updateGroup(_ group: ContractGroup) {
        guard let index = groups.firstIndex(where: { $0.id == group.id }) else { return }
        groups[index] = group
    }

    func deleteGroup(_ group: ContractGroup) {
        groups.removeAll { $0.id == group.id }
        contracts = contracts.map { contract in
            var updated = contract
            if updated.groupID == group.id {
                updated.groupID = nil
            }
            return updated
        }
    }
}
