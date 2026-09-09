import Foundation
import Combine

final class ContractStore: ObservableObject {
    @Published var contracts: [Contract] = []

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
