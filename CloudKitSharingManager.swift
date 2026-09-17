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
                let rootID = CKRecord.ID(recordName: "contract-group-\(stableIdentifier(for: cleanedName))")
                let groupRecord = try await fetchOrCreateGroupRecord(id: rootID, name: cleanedName)
                let contractRecords = contracts
                    .filter { $0.groupName.trimmingCharacters(in: .whitespacesAndNewlines) == cleanedName }
                    .map { makeRecord(for: $0, parent: groupRecord) }

                let share: CKShare
                if let existingShare = try await fetchShare(for: groupRecord.recordID) {
                    share = existingShare
                } else {
                    share = CKShare(rootRecord: groupRecord)
                    share[CKShare.SystemFieldKey.title] = "Groupe de contrats : \(cleanedName)"
                    share.publicPermission = .none
                }

                let recordsToSave = [groupRecord] + contractRecords + [share]
                _ = try await privateDatabase.modifyRecords(saving: recordsToSave, deleting: [])
                sharedGroupNames.insert(cleanedName)
                persistSharedGroupNames()

                let controller = UICloudSharingController { [weak self] sharingController, completionBlock in
                    guard let self else { return }
                    Task {
                        do {
                            let currentShare = try await self.fetchShare(for: groupRecord.recordID) ?? share
                            completionBlock(currentShare, self.container, nil)
                        } catch {
                            completionBlock(nil, self.container, error)
                        }
                    }
                }
                controller.delegate = self
                controller.availablePermissions = [.allowReadWrite]
                viewController.present(controller, animated: true)
                completion(nil)
            } catch {
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
        record.parent = CKRecord.Reference(record: parent, action: .deleteSelf)
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
