import Foundation
import Combine

final class ContractStore: ObservableObject {
    @Published var contracts: [Contract] = []
}
