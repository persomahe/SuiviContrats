import SwiftUI
import UIKit

struct ContractGroupView: View {
    @ObservedObject var store: ContractStore
    @Environment(\.presentationMode) private var presentationMode
    @State private var showingNewGroup = false
    @State private var newGroupName = ""
    @State private var selectedGroup: ContractGroup?

    var body: some View {
        List {
            if store.groups.isEmpty {
                Text("Aucun groupe. Créez un groupe pour organiser et partager vos contrats.")
                    .foregroundColor(.secondary)
            } else {
                ForEach(store.groups) { group in
                    Button {
                        selectedGroup = group
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(group.name)
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Text("\(store.contracts(in: group).count) contrat(s)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if CloudKitSharingManager.shared.isGroupShared(group.name) {
                                Image(systemName: "person.2.fill")
                                    .foregroundColor(.purple)
                            }
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("Groupes de contrats")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { presentationMode.wrappedValue.dismiss() } label: {
                    Image(systemName: "chevron.left")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showingNewGroup = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingNewGroup) {
            NavigationView {
                Form {
                    TextField("Nom du groupe", text: $newGroupName)
                }
                .navigationTitle("Nouveau groupe")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Annuler") { showingNewGroup = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Créer") {
                            store.addGroup(named: newGroupName)
                            newGroupName = ""
                            showingNewGroup = false
                        }
                        .disabled(newGroupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
        .sheet(item: $selectedGroup) { group in
            NavigationView {
                ContractGroupDetailView(group: group, store: store)
            }
        }
    }
}

private struct ContractGroupDetailView: View {
    let group: ContractGroup
    @ObservedObject var store: ContractStore
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var groupIsShared: Bool
    @State private var showingInviteForm = false
    @State private var inviteEmail = ""
    @State private var isInviting = false

    init(group: ContractGroup, store: ContractStore) {
        self.group = group
        self.store = store
        _groupIsShared = State(initialValue: CloudKitSharingManager.shared.isGroupShared(group.name))
    }

    private var contracts: [Contract] { store.contracts(in: group) }

    var body: some View {
        List {
            Section("Contrats") {
                if contracts.isEmpty {
                    Text("Aucun contrat dans ce groupe")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(contracts) { contract in
                        VStack(alignment: .leading) {
                            Text(contract.name.isEmpty ? "Sans nom" : contract.name)
                            Text(contract.provider)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            Section("Partage") {
                if groupIsShared {
                    Text("Ce groupe est partagé. Vous pouvez inviter un participant ou modifier ses droits d’accès.")
                        .font(.footnote)
                        .foregroundColor(.secondary)

                    Button {
                        showingInviteForm = true
                    } label: {
                        Label("Inviter un participant", systemImage: "person.badge.plus")
                    }
                } else {
                    Button {
                        shareGroup()
                    } label: {
                        Label("Partager le groupe", systemImage: "person.2.badge.plus")
                    }
                }
            }
        }
        .navigationTitle(group.name)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Erreur de partage", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .sheet(isPresented: $showingInviteForm) {
            NavigationView {
                Form {
                    Section {
                        TextField("Adresse e-mail Apple", text: $inviteEmail)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } header: {
                        Text("Inviter un participant")
                    } footer: {
                        Text("L’adresse doit être associée au compte Apple/iCloud de l’invité.")
                    }
                }
                .navigationTitle("Invitation")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Annuler") {
                            showingInviteForm = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(isInviting ? "Envoi…" : "Envoyer") {
                            inviteParticipant()
                        }
                        .disabled(isInviting || inviteEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
    }

    private func inviteParticipant() {
        let email = inviteEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty else { return }
        isInviting = true
        CloudKitSharingManager.shared.inviteParticipant(
            named: group.name,
            email: email,
            contracts: contracts
        ) { error in
            isInviting = false
            if let error {
                errorMessage = error.localizedDescription
                showingError = true
            } else {
                inviteEmail = ""
                showingInviteForm = false
                presentShareWhenReady()
            }
        }
    }

    private func presentShareWhenReady(attempt: Int = 0) {
        let maxAttempts = 20
        guard attempt < maxAttempts else {
            errorMessage = "Participant ajouté, mais la feuille de partage n’a pas pu être affichée."
            showingError = true
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            guard let presenter = UIApplication.shared.topMostViewController else {
                presentShareWhenReady(attempt: attempt + 1)
                return
            }

            // La feuille de saisie doit être complètement fermée avant la présentation CloudKit.
            if presenter.presentedViewController != nil {
                presentShareWhenReady(attempt: attempt + 1)
                return
            }

            CloudKitSharingManager.shared.presentShareLink(named: group.name, presenting: presenter) { error in
                if let error {
                    errorMessage = "Participant ajouté, mais le lien n’a pas pu être partagé : \(error.localizedDescription)"
                    showingError = true
                }
            }
        }
    }

    private func shareGroup() {
        guard let presenter = UIApplication.shared.topMostViewController else {
            errorMessage = "Impossible d’afficher la feuille de partage."
            showingError = true
            return
        }
        guard presenter.presentedViewController is UICloudSharingController == false else {
            return
        }
        CloudKitSharingManager.shared.shareGroup(
            named: group.name,
            contracts: contracts,
            presenting: presenter
        ) { error in
            if let error {
                errorMessage = error.localizedDescription
                showingError = true
            } else {
                groupIsShared = true
            }
        }
    }
}

private extension UIApplication {
    var topMostViewController: UIViewController? {
        let root = connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
        return topViewController(from: root)
    }

    func topViewController(from viewController: UIViewController?) -> UIViewController? {
        guard let viewController else { return nil }
        if let presented = viewController.presentedViewController, !presented.isBeingDismissed {
            return topViewController(from: presented)
        }
        if let navigationController = viewController as? UINavigationController {
            return topViewController(from: navigationController.visibleViewController)
        }
        if let tabBarController = viewController as? UITabBarController {
            return topViewController(from: tabBarController.selectedViewController)
        }
        return viewController
    }
}
