import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct ContractBackup: Codable {
    let version: Int
    let exportedAt: Date
    let groups: [ContractGroup]
    let contracts: [Contract]
}

enum DataTransferError: LocalizedError {
    case unsupportedVersion
    case invalidGroupReference

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion:
            return "La version de ce fichier n'est pas compatible."
        case .invalidGroupReference:
            return "Le fichier contient un contrat associé à un groupe inexistant."
        }
    }
}

struct ContractBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    static var writableContentTypes: [UTType] { [.json] }

    var backup: ContractBackup

    init(backup: ContractBackup) {
        self.backup = backup
    }

    init(configuration: ReadConfiguration) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        backup = try decoder.decode(ContractBackup.self, from: configuration.file.regularFileContents ?? Data())
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return FileWrapper(regularFileWithContents: try encoder.encode(backup))
    }
}

struct DataTransferView: View {
    @ObservedObject var store: ContractStore
    @Environment(\.dismiss) private var dismiss
    @State private var sharedFileURL: URL?
    @State private var showingImporter = false
    @State private var showingImportConfirmation = false
    @State private var pendingBackup: ContractBackup?
    @State private var errorMessage: String?
    @State private var showingImportSuccess = false

    private func makeShareFile() throws -> URL {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(store.makeBackup())
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SuiviContrats.json")
        try data.write(to: url, options: .atomic)
        return url
    }

    var body: some View {
        List {
            Section("Partager") {
                Button {
                    do {
                        sharedFileURL = try makeShareFile()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                } label: {
                    Label("Partager mes données", systemImage: "square.and.arrow.up")
                }

                if let sharedFileURL {
                    ShareLink(
                        item: sharedFileURL,
                        subject: Text("Données SuiviContrats"),
                        message: Text("Voici mes données SuiviContrats.")
                    ) {
                        Label("Choisir le destinataire", systemImage: "paperplane")
                    }
                }
            }

            Section("Importer") {
                Button {
                    showingImporter = true
                } label: {
                    Label("Importer des données", systemImage: "square.and.arrow.down")
                }

                Text("L'import remplace les groupes et les contrats actuellement enregistrés dans l'application.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle("Partage de données")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Fermer") { dismiss() }
            }
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            do {
                guard let url = try result.get().first else { return }

                let accessGranted = url.startAccessingSecurityScopedResource()
                defer {
                    if accessGranted {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                let data = try Data(contentsOf: url)
                let backup = try store.decodeBackup(from: data)
                pendingBackup = backup
                showingImportConfirmation = true
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        .confirmationDialog(
            "Remplacer les données actuelles ?",
            isPresented: $showingImportConfirmation,
            titleVisibility: .visible
        ) {
            Button("Importer", role: .destructive) {
                guard let pendingBackup else { return }
                store.restore(backup: pendingBackup)
                self.pendingBackup = nil
                showingImportSuccess = true
            }
            Button("Annuler", role: .cancel) {
                pendingBackup = nil
            }
        } message: {
            Text("Les groupes et les contrats actuels seront remplacés par ceux du fichier sélectionné.")
        }
        .alert("Import réussi.", isPresented: $showingImportSuccess) {
            Button("OK", role: .cancel) { }
        }
        .alert("Erreur", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Une erreur est survenue.")
        }
    }
}

struct DataTransferView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            DataTransferView(store: PreviewData.contractStore)
        }
    }
}
