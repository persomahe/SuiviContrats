import CloudKit
import UIKit

@MainActor
final class CloudKitSharingManager: NSObject, ObservableObject {
    static let shared = CloudKitSharingManager()
    static let containerIdentifier = "iCloud.com.cmahe.SuiviContrats"

    private let container: CKContainer
    private let privateDatabase: CKDatabase
    private let sharedGroupKey = "sharedContractGroups"
    private var sharedGroupNames: Set<String>

    private enum SharingError: LocalizedError {
        case accountUnavailable(CKAccountStatus)

        var errorDescription: String? {
            switch self {
            case .accountUnavailable(let status):
                switch status {
                case .noAccount:
                    return "Aucun compte iCloud n’est connecté sur cet appareil. Connectez-vous à iCloud dans Réglages, puis réessayez."
                case .restricted:
                    return "L’accès à iCloud est restreint sur cet appareil."
                case .couldNotDetermine:
                    return "L’état du compte iCloud ne peut pas être déterminé. Vérifiez la connexion Internet et réessayez."
                case .temporarilyUnavailable:
                    return "Le compte iCloud est temporairement indisponible. Réessayez dans quelques instants."
                case .available:
                    return nil
                @unknown default:
                    return "Le compte iCloud n’est pas disponible pour le partage."
                }
            }
        }
    }

    private override init() {
        container = CKContainer(identifier: Self.containerIdentifier)
        privateDatabase = container.privateCloudDatabase
        sharedGroupNames = Set(UserDefaults.standard.stringArray(forKey: sharedGroupKey) ?? [])
        super.init()
    }

    func isGroupShared(_ groupName: String) -> Bool {
        sharedGroupNames.contains(groupName)
    }

    func shareGroup(named groupName: String, contracts: [Contract], presenting viewController: UIViewController, completion: @escaping (Error?) -> Void = { _ in }) {
        let cleanedName = groupName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedName.isEmpty else { return }

        Task {
            do {
                let accountStatus = try await container.accountStatus()
                let currentUserRecordID = try await container.userRecordID()
                print("Bundle ID :", Bundle.main.bundleIdentifier ?? "inconnu")
                print("Entitlements iCloud signés : diagnostic indisponible sur iOS")
                print("[CloudKit] Conteneur : \(Self.containerIdentifier)")
                print("[CloudKit] État du compte : \(accountStatus)")
                print("[CloudKit] Utilisateur CloudKit courant : \(currentUserRecordID.recordName)")
                guard accountStatus == .available else {
                    throw SharingError.accountUnavailable(accountStatus)
                }

                let rootID = CKRecord.ID(recordName: "contract-group-\(stableIdentifier(for: cleanedName))")
                let groupRecord = try await fetchOrCreateGroupRecord(id: rootID, name: cleanedName)
                let contractRecords = contracts
                    .filter { $0.groupName.trimmingCharacters(in: .whitespacesAndNewlines) == cleanedName }
                    .map { makeRecord(for: $0, parent: groupRecord) }

                let share: CKShare
                let existingShare: CKShare?
                if let fetchedShare = try await fetchShare(for: groupRecord.recordID) {
                    share = fetchedShare
                    existingShare = fetchedShare
                } else {
                    share = CKShare(rootRecord: groupRecord)
                    share[CKShare.SystemFieldKey.title] = "Groupe de contrats : \(cleanedName)"
                    share.publicPermission = .none
                    existingShare = nil
                }

                print("[CloudKit] Groupe : \(cleanedName)")
                print("[CloudKit] Groupe ID : \(groupRecord.recordID.recordName)")
                print("[CloudKit] Nombre de contrats partagés : \(contractRecords.count)")
                print("[CloudKit] CKShare existant : \(existingShare != nil)")

                let recordsToSave = [groupRecord] + contractRecords + [share]
                _ = try await privateDatabase.modifyRecords(saving: recordsToSave, deleting: [])
                sharedGroupNames.insert(cleanedName)
                persistSharedGroupNames()

                print("[CloudKit] Propriétaire du CKShare : \(share.owner.userIdentity)")
                print("[CloudKit] Rôle du propriétaire : \(share.owner.role.rawValue)")
                print("[CloudKit] Permission du propriétaire : \(share.owner.permission.rawValue)")
                if let currentParticipant = share.currentUserParticipant {
                    print("[CloudKit] Participant courant : \(currentParticipant.userIdentity)")
                    print("[CloudKit] Rôle du participant courant : \(currentParticipant.role.rawValue)")
                    print("[CloudKit] Permission du participant courant : \(currentParticipant.permission.rawValue)")
                } else {
                    print("[CloudKit] Aucun participant courant associé au CKShare")
                }
                print("[CloudKit] Permission publique : \(share.publicPermission.rawValue)")

                let controller = UICloudSharingController(share: share, container: container)
                controller.delegate = self
                controller.availablePermissions = [.allowReadWrite]
                DispatchQueue.main.async {
                    guard viewController.viewIfLoaded?.window != nil else {
                        let error = NSError(
                            domain: "CloudKitSharingManager",
                            code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "Impossible d’afficher la feuille de partage depuis l’écran courant."]
                        )
                        completion(error)
                        return
                    }
                    viewController.present(controller, animated: true)
                    completion(nil)
                }
            } catch {
                if let cloudKitError = error as? CKError {
                    print("[CloudKit] Code erreur : \(cloudKitError.code.rawValue)")
                    print("[CloudKit] Détail erreur : \(cloudKitError.localizedDescription)")
                    print("[CloudKit] UserInfo : \(cloudKitError.userInfo)")
                }
                print("Erreur CloudKit lors du partage du groupe : \(error)")
                completion(error)
            }
        }
    }

    private func persistSharedGroupNames() {
        UserDefaults.standard.set(Array(sharedGroupNames), forKey: sharedGroupKey)
    }

    private func fetchOrCreateGroupRecord(id: CKRecord.ID, name: String) async throws -> CKRecord {
        do {
            return try await privateDatabase.record(for: id)
        } catch let error as CKError where error.code == .unknownItem {
            let record = CKRecord(recordType: "ContractGroup", recordID: id)
            record["name"] = name as CKRecordValue
            return record
        }
    }

    private func fetchShare(for recordID: CKRecord.ID) async throws -> CKShare? {
        try await withCheckedThrowingContinuation { continuation in
            let operation = CKFetchRecordsOperation(recordIDs: [recordID])
            var fetchedShare: CKShare?

            operation.perRecordResultBlock = { _, result in
                if case .success(let record) = result {
                    fetchedShare = record as? CKShare
                }
            }
            operation.fetchRecordsResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume(returning: fetchedShare)
                case .failure(let error):
                    if let ckError = error as? CKError, ckError.code == .unknownItem {
                        continuation.resume(returning: nil)
                    } else {
                        continuation.resume(throwing: error)
                    }
                }
            }
            privateDatabase.add(operation)
        }
    }

    private func makeRecord(for contract: Contract, parent: CKRecord) -> CKRecord {
        let record = CKRecord(recordType: "Contract", recordID: CKRecord.ID(recordName: "contract-\(contract.id.uuidString)"))
        record.parent = CKRecord.Reference(record: parent, action: .none)
        record["id"] = contract.id.uuidString as CKRecordValue
        record["groupName"] = contract.groupName as CKRecordValue
        record["name"] = contract.name as CKRecordValue
        record["category"] = contract.category as CKRecordValue
        record["provider"] = contract.provider as CKRecordValue
        record["anniversaryDate"] = contract.anniversaryDate as CKRecordValue
        record["cancellationNoticeMonths"] = contract.cancellationNoticeMonths as CKRecordValue
        record["amountType"] = contract.amountType.rawValue as CKRecordValue
        record["amount"] = contract.amount as CKRecordValue
        // CloudKit does not accept a Swift array directly as a record value.
        record["annualAmounts"] = try? JSONEncoder().encode(contract.annualAmounts) as NSData
        record["status"] = contract.status as CKRecordValue
        record["comment"] = contract.comment as CKRecordValue
        return record
    }

    private func stableIdentifier(for value: String) -> String {
        value.unicodeScalars.map { String(format: "%02X", $0.value) }.joined()
    }
}

extension CloudKitSharingManager: UICloudSharingControllerDelegate {
    func itemTitle(for csc: UICloudSharingController) -> String? { "Groupe de contrats" }
    func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {}
    func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {}
    func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
        print("Erreur de partage CloudKit : \(error)")
    }
}

private extension UIApplication {
    var firstKeyWindowRootViewController: UIViewController? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
    }
}
