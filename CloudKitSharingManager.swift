import CloudKit
import UIKit

@MainActor
final class CloudKitSharingManager: NSObject, ObservableObject {
    static let shared = CloudKitSharingManager()
    static let containerIdentifier = "iCloud.com.cmahe.SuiviContrats"

    private let container: CKContainer
    private let privateDatabase: CKDatabase
    private let sharedGroupKey = "sharedContractGroups"
    private let groupZoneID = CKRecordZone.ID(zoneName: "ContractGroups", ownerName: CKCurrentUserDefaultName)
    private var sharedGroupNames: Set<String>
    private var cachedShares: [String: CKShare]
    private var cachedGroupRecords: [String: CKRecord]

    private enum SharingError: LocalizedError {
        case accountUnavailable(CKAccountStatus)

        var errorDescription: String? {
            switch self {
            case .accountUnavailable(let status):
                switch status {
                case .noAccount: return "Aucun compte iCloud n’est connecté sur cet appareil."
                case .restricted: return "L’accès à iCloud est restreint sur cet appareil."
                case .couldNotDetermine: return "L’état du compte iCloud ne peut pas être déterminé."
                case .temporarilyUnavailable: return "Le compte iCloud est temporairement indisponible."
                case .available: return nil
                @unknown default: return "Le compte iCloud n’est pas disponible pour le partage."
                }
            }
        }
    }

    private override init() {
        container = CKContainer(identifier: Self.containerIdentifier)
        privateDatabase = container.privateCloudDatabase
        sharedGroupNames = Set(UserDefaults.standard.stringArray(forKey: sharedGroupKey) ?? [])
        cachedShares = [:]
        cachedGroupRecords = [:]
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
                guard accountStatus == .available else { throw SharingError.accountUnavailable(accountStatus) }

                try await ensureGroupZone()
                let rootID = CKRecord.ID(recordName: "contract-group-\(stableIdentifier(for: cleanedName))", zoneID: groupZoneID)
                let groupRecord = try await fetchOrCreateGroupRecord(id: rootID, name: cleanedName)
                let contractRecords = try await recordsForSaving(
                    contracts.filter { $0.groupName.trimmingCharacters(in: .whitespacesAndNewlines) == cleanedName },
                    parent: groupRecord
                )

                var persistedGroupRecord = groupRecord
                if groupRecord.recordChangeTag == nil {
                    let savedInitialRecords = try await saveRecords([groupRecord] + contractRecords)
                    persistedGroupRecord = (savedInitialRecords.first { $0.recordID == groupRecord.recordID }) ?? groupRecord
                    print("[CloudKit] Groupe et nouveaux contrats enregistrés avant la création du partage")
                } else {
                    let newContractRecords = contractRecords.filter { $0.recordChangeTag == nil }
                    if !newContractRecords.isEmpty {
                        _ = try await saveRecords(newContractRecords)
                        print("[CloudKit] Nouveaux contrats enregistrés dans le groupe existant")
                    }
                }

                let share: CKShare
                let shareIsNew: Bool
                if let existing = try await fetchShare(for: persistedGroupRecord.recordID) {
                    share = existing
                    shareIsNew = false
                } else {
                    share = CKShare(rootRecord: persistedGroupRecord)
                    share[CKShare.SystemFieldKey.title] = "Groupe de contrats : \(cleanedName)"
                    share.publicPermission = .none
                    shareIsNew = true
                }

                print("[CloudKit] Groupe : \(cleanedName)")
                print("[CloudKit] Groupe ID : \(persistedGroupRecord.recordID.recordName)")
                print("[CloudKit] Groupe zone : \(persistedGroupRecord.recordID.zoneID.zoneName)")
                print("[CloudKit] Nombre de contrats partagés : \(contractRecords.count)")
                print("[CloudKit] CKShare existant : \(persistedGroupRecord.share != nil)")

                // Le groupe racine est déjà enregistré avant la création du CKShare.
                // Un CKShare existant est sauvegardé seul.
                let savedRecords = try await saveRecords(shareIsNew ? [persistedGroupRecord, share] : [share])
                let savedGroupRecord = (savedRecords.first { $0.recordID == persistedGroupRecord.recordID }) ?? persistedGroupRecord
                let savedShare = (savedRecords.first { $0.recordID == share.recordID } as? CKShare) ?? share
                cachedGroupRecords[cleanedName] = savedGroupRecord
                cachedShares[cleanedName] = savedShare
                sharedGroupNames.insert(cleanedName)
                persistSharedGroupNames()

                print("[CloudKit] Groupe sauvegardé : \(savedGroupRecord.recordID.recordName)")
                print("[CloudKit] CKShare sauvegardé : \(savedShare.recordID.recordName)")
                if let url = savedShare.url {
                    print("[CloudKit] Lien d’invitation créé : \(url.absoluteString)")
                } else {
                    print("[CloudKit] CKShare sauvegardé, URL non disponible ; UICloudSharingController sera utilisé")
                }

                printShareDiagnostics(savedShare)
                let controller = UICloudSharingController(share: savedShare, container: container)
                controller.delegate = self
                controller.availablePermissions = [.allowReadWrite, .allowReadOnly]

                DispatchQueue.main.async {
                    guard viewController.presentedViewController == nil,
                          viewController.viewIfLoaded?.window != nil else {
                        completion(NSError(domain: "CloudKitSharingManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Une autre feuille est déjà affichée."]))
                        return
                    }
                    viewController.present(controller, animated: true)
                    completion(nil)
                }
            } catch {
                log(error)
                completion(error)
            }
        }
    }

    // Replace the existing inviteParticipant(named:email:completion:) method with a version that also receives contracts.
    func inviteParticipant(named groupName: String, email: String, contracts: [Contract], completion: @escaping (Error?) -> Void = { _ in }) {
        let cleanedName = groupName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedName.isEmpty, !cleanedEmail.isEmpty else { return }

        Task {
            do {
                let status = try await container.accountStatus()
                guard status == .available else { throw SharingError.accountUnavailable(status) }
                try await ensureGroupZone()
                let groupID = CKRecord.ID(recordName: "contract-group-\(stableIdentifier(for: cleanedName))", zoneID: groupZoneID)
                let groupRecord = try await fetchOrCreateGroupRecord(id: groupID, name: cleanedName)
                let contractRecords = try await recordsForSaving(
                    contracts.filter { $0.groupName.trimmingCharacters(in: .whitespacesAndNewlines) == cleanedName },
                    parent: groupRecord
                )

                var persistedGroupRecord = groupRecord
                if groupRecord.recordChangeTag == nil {
                    let savedInitialRecords = try await saveRecords([groupRecord] + contractRecords)
                    persistedGroupRecord = (savedInitialRecords.first { $0.recordID == groupRecord.recordID }) ?? groupRecord
                }

                let share: CKShare
                let shareIsNew: Bool
                if let cachedShare = cachedShares[cleanedName] {
                    share = cachedShare
                    shareIsNew = false
                } else if let fetchedShare = try await fetchShare(for: persistedGroupRecord.recordID) {
                    share = fetchedShare
                    shareIsNew = false
                } else {
                    share = CKShare(rootRecord: persistedGroupRecord)
                    share[CKShare.SystemFieldKey.title] = "Groupe de contrats : \(cleanedName)"
                    share.publicPermission = .none
                    shareIsNew = true
                }

                let lookupInfo = CKUserIdentity.LookupInfo(emailAddress: cleanedEmail)
                guard let participant = try await fetchShareParticipant(for: lookupInfo) else {
                    throw NSError(domain: "CloudKitSharingManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "Aucun compte iCloud correspondant à cette adresse n’a été trouvé."])
                }
                participant.permission = .readWrite
                share.addParticipant(participant)
                share.publicPermission = .none

                if shareIsNew {
                    let newRecords = [persistedGroupRecord] + contractRecords.filter { $0.recordChangeTag == nil }
                    if !newRecords.isEmpty {
                        _ = try await saveRecords(newRecords)
                    }
                }
                let savedRecords = try await saveRecords([share])
                let savedGroupRecord = persistedGroupRecord
                let savedShare = (savedRecords.first { $0.recordID == share.recordID } as? CKShare) ?? share
                cachedGroupRecords[cleanedName] = savedGroupRecord
                cachedShares[cleanedName] = savedShare
                sharedGroupNames.insert(cleanedName)
                persistSharedGroupNames()
                print("[CloudKit] Participant ajouté au CKShare : \(savedShare.recordID.recordName)")
                if let url = savedShare.url {
                    print("[CloudKit] Lien d’invitation disponible : \(url.absoluteString)")
                } else {
                    print("[CloudKit] Lien URL indisponible ; ouverture de la feuille Apple")
                }

                // Après l’ajout d’un participant, la sauvegarde du CKShare a réussi.
                completion(nil)
            } catch {
                log(error)
                completion(error)
            }
        }
    }

    func presentShare(named groupName: String, presenting viewController: UIViewController, completion: @escaping (Error?) -> Void = { _ in }) {
        let cleanedName = groupName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedName.isEmpty else { return }

        Task {
            do {
                let share: CKShare
                if let cachedShare = cachedShares[cleanedName] {
                    share = cachedShare
                } else {
                    let groupID = CKRecord.ID(recordName: "contract-group-\(stableIdentifier(for: cleanedName))", zoneID: groupZoneID)
                    let groupRecord = try await privateDatabase.record(for: groupID)
                    guard let fetchedShare = try await fetchShare(for: groupRecord.recordID) else {
                        throw NSError(domain: "CloudKitSharingManager", code: 6, userInfo: [NSLocalizedDescriptionKey: "Le partage de ce groupe n’est pas disponible."])
                    }
                    share = fetchedShare
                    cachedShares[cleanedName] = fetchedShare
                    cachedGroupRecords[cleanedName] = groupRecord
                }

                let controller = UICloudSharingController(share: share, container: container)
                controller.delegate = self
                controller.availablePermissions = [.allowReadWrite, .allowReadOnly]
                DispatchQueue.main.async {
                    guard viewController.presentedViewController == nil,
                          viewController.viewIfLoaded?.window != nil else {
                        completion(NSError(domain: "CloudKitSharingManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Une autre feuille est déjà affichée."]))
                        return
                    }
                    viewController.present(controller, animated: true)
                    completion(nil)
                }
            } catch {
                log(error)
                completion(error)
            }
        }
    }

    func presentShareLink(named groupName: String, presenting viewController: UIViewController, completion: @escaping (Error?) -> Void = { _ in }) {
        let cleanedName = groupName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedName.isEmpty else { return }

        Task {
            do {
                let share: CKShare
                if let cachedShare = cachedShares[cleanedName] {
                    share = try await fetchShareWithURL(for: cleanedName, cachedShare: cachedShare)
                } else {
                    let groupID = CKRecord.ID(
                        recordName: "contract-group-\(stableIdentifier(for: cleanedName))",
                        zoneID: groupZoneID
                    )
                    let groupRecord = try await privateDatabase.record(for: groupID)
                    guard let fetchedShare = try await fetchShare(for: groupRecord.recordID) else {
                        throw NSError(
                            domain: "CloudKitSharingManager",
                            code: 6,
                            userInfo: [NSLocalizedDescriptionKey: "Le partage de ce groupe n’est pas disponible."]
                        )
                    }
                    share = try await fetchShareWithURL(for: cleanedName, cachedShare: fetchedShare)
                }

                guard let url = share.url else {
                    throw NSError(
                        domain: "CloudKitSharingManager",
                        code: 7,
                        userInfo: [NSLocalizedDescriptionKey: "Le lien d’invitation CloudKit n’est pas disponible."]
                    )
                }

                print("[CloudKit] Ouverture de la feuille d’envoi avec le lien : \(url.absoluteString)")
                presentActivityController(for: url, from: viewController, completion: completion)
            } catch {
                log(error)
                completion(error)
            }
        }
    }

    private func saveRecords(_ records: [CKRecord]) async throws -> [CKRecord] {
        do {
            let result = try await privateDatabase.modifyRecords(saving: records, deleting: [])
            var savedRecords: [CKRecord] = []
            for record in records {
                if let saved = try result.saveResults[record.recordID]?.get() {
                    savedRecords.append(saved)
                }
            }
            return savedRecords
        } catch {
            print("[CloudKit] Échec de sauvegarde atomique pour : \(records.map { "\($0.recordType):\($0.recordID.recordName)" }.joined(separator: ", "))")
            throw error
        }
    }

    private func ensureGroupZone() async throws {
        let zone = CKRecordZone(zoneID: groupZoneID)
        do {
            _ = try await privateDatabase.modifyRecordZones(saving: [zone], deleting: [])
            print("[CloudKit] Zone personnalisée prête pour le partage : \(groupZoneID.zoneName)")
        } catch let error as CKError where error.code == .serverRejectedRequest {
            // CloudKit accepte normalement la sauvegarde idempotente d'une zone existante.
            print("[CloudKit] Zone personnalisée déjà disponible : \(groupZoneID.zoneName)")
        }
    }

    private func fetchShareParticipant(for lookupInfo: CKUserIdentity.LookupInfo) async throws -> CKShare.Participant? {
        try await withCheckedThrowingContinuation { continuation in
            let operation = CKFetchShareParticipantsOperation(userIdentityLookupInfos: [lookupInfo])
            var participant: CKShare.Participant?
            var operationError: Error?
            operation.perShareParticipantResultBlock = { _, result in
                switch result {
                case .success(let value): participant = value
                case .failure(let error): operationError = error
                }
            }
            operation.fetchShareParticipantsResultBlock = { result in
                if let operationError { continuation.resume(throwing: operationError) }
                else {
                    switch result {
                    case .success: continuation.resume(returning: participant)
                    case .failure(let error): continuation.resume(throwing: error)
                    }
                }
            }
            self.container.add(operation)
        }
    }

    private func persistSharedGroupNames() {
        UserDefaults.standard.set(Array(sharedGroupNames), forKey: sharedGroupKey)
    }

    private func fetchOrCreateGroupRecord(id: CKRecord.ID, name: String) async throws -> CKRecord {
        do { return try await privateDatabase.record(for: id) }
        catch let error as CKError where error.code == .unknownItem {
            print("[CloudKit] Création du groupe dans la zone : \(id.zoneID.zoneName)")
            let record = CKRecord(recordType: "ContractGroup", recordID: id)
            record["name"] = name as CKRecordValue
            return record
        }
    }

    private func fetchShare(for recordID: CKRecord.ID) async throws -> CKShare? {
        print("[CloudKit] Recherche du groupe dans la zone : \(recordID.zoneID.zoneName)")
        do {
            let record = try await privateDatabase.record(for: recordID)
            guard let shareReference = record.share else {
                print("[CloudKit] Aucun CKShare associé au groupe : \(recordID.recordName)")
                return nil
            }
            let shareRecord = try await privateDatabase.record(for: shareReference.recordID)
            return shareRecord as? CKShare
        } catch let error as CKError where error.code == .unknownItem {
            print("[CloudKit] Groupe introuvable lors de la recherche du CKShare : \(recordID.recordName)")
            return nil
        }
    }

    private func recordsForSaving(_ contracts: [Contract], parent: CKRecord) async throws -> [CKRecord] {
        var records: [CKRecord] = []
        for contract in contracts {
            let recordID = CKRecord.ID(
                recordName: "contract-\(contract.id.uuidString)",
                zoneID: parent.recordID.zoneID
            )
            do {
                // Réutiliser le record existant conserve son changeTag et évite un conflit
                // atomique lorsque le partage est rouvert ou qu'un invité est ajouté.
                let existing = try await privateDatabase.record(for: recordID)
                records.append(existing)
            } catch let error as CKError where error.code == .unknownItem {
                records.append(makeRecord(for: contract, parent: parent))
            }
        }
        return records
    }

    private func makeRecord(for contract: Contract, parent: CKRecord) -> CKRecord {
        let recordID = CKRecord.ID(
            recordName: "contract-\(contract.id.uuidString)",
            zoneID: parent.recordID.zoneID
        )
        let record = CKRecord(recordType: "Contract", recordID: recordID)
        print("[CloudKit] Création d’un contrat dans la zone : \(parent.recordID.zoneID.zoneName)")
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
        record["annualAmounts"] = try? JSONEncoder().encode(contract.annualAmounts) as NSData
        record["status"] = contract.status as CKRecordValue
        record["comment"] = contract.comment as CKRecordValue
        return record
    }

    private func stableIdentifier(for value: String) -> String {
        value.unicodeScalars.map { String(format: "%02X", $0.value) }.joined()
    }

    private func fetchShareWithURL(for groupName: String, cachedShare: CKShare) async throws -> CKShare {
        print("[CloudKit] Recherche du lien d’invitation pour le groupe : \(groupName)")
        print("[CloudKit] Share recordID initial : \(cachedShare.recordID.recordName)")
        if let url = cachedShare.url {
            print("[CloudKit] Lien déjà disponible : \(url.absoluteString)")
            return cachedShare
        }

        let groupID = CKRecord.ID(
            recordName: "contract-group-\(stableIdentifier(for: groupName))",
            zoneID: groupZoneID
        )
        for attempt in 0..<5 {
            print("[CloudKit] Tentative \(attempt + 1)/5 de récupération du CKShare")
            if let groupRecord = try? await privateDatabase.record(for: groupID),
               let refreshedShare = try? await fetchShare(for: groupRecord.recordID) {
                if let url = refreshedShare.url {
                    print("[CloudKit] Lien d’invitation créé/récupéré : \(url.absoluteString)")
                    print("[CloudKit] Share recordID final : \(refreshedShare.recordID.recordName)")
                    cachedGroupRecords[groupName] = groupRecord
                    cachedShares[groupName] = refreshedShare
                    return refreshedShare
                }
                print("[CloudKit] CKShare récupéré, mais son URL est encore absente")
            } else {
                print("[CloudKit] Impossible de relire le groupe ou le CKShare à cette tentative")
            }
            if attempt < 4 {
                try await Task.sleep(nanoseconds: 500_000_000)
            }
        }
        print("[CloudKit] Aucun lien d’invitation disponible après 5 tentatives")
        return cachedShare
    }

    private func printShareDiagnostics(_ share: CKShare) {
        print("[CloudKit] Propriétaire du CKShare : \(share.owner.userIdentity)")
        print("[CloudKit] Rôle du propriétaire : \(share.owner.role.rawValue)")
        print("[CloudKit] Permission du propriétaire : \(share.owner.permission.rawValue)")
        print("[CloudKit] Permission publique : \(share.publicPermission.rawValue)")
    }

    private func presentActivityController(for url: URL, from viewController: UIViewController, completion: @escaping (Error?) -> Void) {
        guard viewController.presentedViewController == nil,
              viewController.viewIfLoaded?.window != nil else {
            completion(NSError(
                domain: "CloudKitSharingManager",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Une autre feuille est déjà affichée."]
            ))
            return
        }

        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let popover = controller.popoverPresentationController {
            popover.sourceView = viewController.view
            popover.sourceRect = CGRect(
                x: viewController.view.bounds.midX,
                y: viewController.view.bounds.midY,
                width: 1,
                height: 1
            )
        }
        controller.completionWithItemsHandler = { activityType, completed, _, error in
            if let error {
                print("[CloudKit] Échec de l’envoi du lien (\(activityType?.rawValue ?? "inconnu")) : \(error)")
            } else {
                print("[CloudKit] Feuille d’envoi terminée. Activité : \(activityType?.rawValue ?? "aucune"), envoyé : \(completed)")
            }
        }
        viewController.present(controller, animated: true) {
            print("[CloudKit] Feuille Mail/Messages/AirDrop présentée")
            completion(nil)
        }
    }

    private func log(_ error: Error) {
        if let cloudKitError = error as? CKError {
            print("[CloudKit] Code erreur : \(cloudKitError.code.rawValue)")
            print("[CloudKit] Détail erreur : \(cloudKitError.localizedDescription)")
            print("[CloudKit] UserInfo : \(cloudKitError.userInfo)")
        }
        print("Erreur CloudKit : \(error)")
    }
}

extension CloudKitSharingManager: UICloudSharingControllerDelegate {
    func itemTitle(for csc: UICloudSharingController) -> String? { "Groupe de contrats" }
    func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {}
    func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {}
    func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) { log(error) }
}
