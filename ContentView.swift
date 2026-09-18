import SwiftUI
import CloudKit
import UIKit

struct ContentView: View {
    @StateObject private var store: ContractStore
    @State private var showingNewContract = false
    @State private var showingContracts = false
    @State private var showingNotificationSettings = false

    init(store: ContractStore = ContractStore()) {
        _store = StateObject(wrappedValue: store)
    }

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 8),
        count: 3
    )

    private var contractsByUrgency: [Contract] {
        store.contracts
            .filter { $0.status != "Résilié" }
            .sorted {
                urgency(for: $0.anniversaryDate) > urgency(for: $1.anniversaryDate)
            }
    }

    private func urgency(for date: Date) -> Double {
        let calendar = Calendar.current
        let now = Date()
        let currentYear = calendar.component(.year, from: now)
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        let thisYearDate = anniversaryDate(year: currentYear, month: month, day: day, calendar: calendar)
        let nextDate = thisYearDate > now
            ? thisYearDate
            : anniversaryDate(year: currentYear + 1, month: month, day: day, calendar: calendar)
        let previousDate = anniversaryDate(
            year: currentYear - (thisYearDate > now ? 1 : 0),
            month: month,
            day: day,
            calendar: calendar
        )
        let total = max(nextDate.timeIntervalSince(previousDate), 1)
        let remaining = max(nextDate.timeIntervalSince(now), 0)
        return min(max(1 - remaining / total, 0), 1)
    }

    private func anniversaryDate(year: Int, month: Int, day: Int, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))
            ?? calendar.date(from: DateComponents(year: year, month: month, day: min(day, 28)))
            ?? Date()
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Tableau de bord")
                        .font(.title.bold())

                    if store.contracts.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 40))
                                .foregroundColor(.secondary)
                            Text("Aucun contrat")
                                .font(.headline)
                            Text("Ajoutez vos contrats depuis le menu.")
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 30)
                    } else {
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(contractsByUrgency) { contract in
                                NavigationLink(destination: ContractDetailView(contract: contract, store: store)) {
                                    ContractDashboardCard(contract: contract)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal)
                .padding(.top, 1)
                .padding(.bottom)
            }
            .background(Color.appBackground.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            showingNewContract = true
                        } label: {
                            Label("Nouveau contrat", systemImage: "plus.circle")
                        }
                        Button {
                            showingContracts = true
                        } label: {
                            Label("Mes contrats", systemImage: "list.bullet.rectangle")
                        }
                        Button {
                            showingNotificationSettings = true
                        } label: {
                            Label("Gérer les notifications", systemImage: "bell.badge")
                        }
                        Divider()
                        Text("Autres fonctionnalités à venir")
                    } label: {
                        Image(systemName: "line.3.horizontal")
                            .accessibilityLabel("Menu")
                    }
                }
            }
            .sheet(isPresented: $showingNewContract) {
                ContractEditorView(contract: Contract(), groupNames: store.groupNames) { contract in
                    let isFirstContract = store.contracts.isEmpty
                    store.add(contract)
                    showingNewContract = false
                    if isFirstContract {
                        Task { await NotificationManager.shared.requestAuthorization() }
                    }
                }
            }
            .sheet(isPresented: $showingContracts) {
                NavigationView {
                    ContractView(store: store)
                }
            }
            .sheet(isPresented: $showingNotificationSettings) {
                NotificationSettingsView()
            }
        }
        .background(Color.appBackground.ignoresSafeArea())
        .navigationViewStyle(StackNavigationViewStyle())
        .dynamicTypeSize(.medium)
    }
}

private struct ContractDashboardCard: View {
    let contract: Contract

    private var anniversarySummary: String {
        let date = contract.anniversaryDate
            .formatted(
                .dateTime
                    .day()
                    .month(.abbreviated)
                    .locale(Locale(identifier: "fr_FR"))
            )
            .replacingOccurrences(of: ".", with: "")
        let notice = contract.cancellationNoticeMonths == 0
            ? "Aucun délai"
            : "\(contract.cancellationNoticeMonths) mois"
        return "\(date) - \(notice)"
    }

    var body: some View {
        VStack(spacing: 10) {
            Text(contract.name.isEmpty ? "Sans nom" : contract.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 36)

            AnniversaryProgressRing(contract: contract)

            Text(anniversarySummary)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)

            Text(contract.status)
                .font(.caption2.weight(.medium))
                .foregroundColor(contract.status == "Résilié" ? .red : .green)
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 155)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.gray.opacity(0.15), lineWidth: 1)
        )
    }
}

private struct AnniversaryProgressRing: View {
    let contract: Contract

    private var progress: Double {
        let calendar = Calendar.current
        let now = Date()
        let anniversary = contract.anniversaryDate
        let month = calendar.component(.month, from: anniversary)
        let day = calendar.component(.day, from: anniversary)
        let noticeMonths = contract.cancellationNoticeMonths

        let currentYear = calendar.component(.year, from: now)
        let thisYearAnniversary = anniversaryDate(
            year: currentYear,
            month: month,
            day: day,
            calendar: calendar
        )
        let thisYearDeadline = calendar.date(
            byAdding: .month,
            value: -noticeMonths,
            to: thisYearAnniversary
        ) ?? thisYearAnniversary

        let nextDeadline: Date
        let previousDeadline: Date
        if thisYearDeadline > now {
            nextDeadline = thisYearDeadline
            previousDeadline = calendar.date(
                byAdding: .year,
                value: -1,
                to: thisYearDeadline
            ) ?? thisYearDeadline
        } else {
            nextDeadline = calendar.date(
                byAdding: .year,
                value: 1,
                to: thisYearDeadline
            ) ?? thisYearDeadline
            previousDeadline = thisYearDeadline
        }

        let total = max(nextDeadline.timeIntervalSince(previousDeadline), 1)
        let remaining = max(nextDeadline.timeIntervalSince(now), 0)
        return min(max(1 - remaining / total, 0), 1)
    }

    private func anniversaryDate(year: Int, month: Int, day: Int, calendar: Calendar) -> Date {
        if let result = calendar.date(from: DateComponents(year: year, month: month, day: day)) {
            return result
        }
        return calendar.date(from: DateComponents(year: year, month: month, day: min(day, 28))) ?? Date()
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.green.opacity(0.18), lineWidth: 10)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(
                        colors: [.green, .green, .yellow, .red, .red],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut, value: progress)
            Image(systemName: "calendar")
                .font(.title2)
                .foregroundColor(.green)
        }
        .frame(width: 65, height: 65)
        .accessibilityLabel("Progression vers la prochaine date anniversaire")
        .accessibilityValue("\(Int(progress * 100)) pour cent")
    }
}

private struct ContractDetailView: View {
    let contract: Contract
    let store: ContractStore
    @State private var showingEditor = false
    @State private var showingShareUnavailableAlert = false
    @State private var showingShareError = false
    @State private var shareErrorMessage = ""

    private var trimmedGroupName: String {
        contract.groupName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Form {
            if !trimmedGroupName.isEmpty {
                Section {
                    DetailRow(label: "Groupe", value: trimmedGroupName)
                    Button {
                        shareGroup()
                    } label: {
                        Label(
                            CloudKitSharingManager.shared.isGroupShared(trimmedGroupName)
                                ? "Groupe déjà partagé"
                                : "Partager le groupe",
                            systemImage: CloudKitSharingManager.shared.isGroupShared(trimmedGroupName)
                                ? "person.2.fill"
                                : "person.2.badge.plus"
                        )
                    }
                    .disabled(false)
                } header: {
                    Text("Partage")
                        .foregroundColor(.purple)
                }
            }
            Text(contract.name.isEmpty ? "Contrat" : contract.name)
                .font(.title)
                .foregroundColor(.green)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
                .lineLimit(2)
            Section {
                DetailRow(label: "Catégorie", value: contract.category)
                DetailRow(label: "Fournisseur", value: contract.provider.isEmpty ? "Non renseigné" : contract.provider)
                DetailRow(label: "Statut", value: contract.status)
            } header: {
                Text("Informations")
                    .foregroundColor(.purple)
            }
            Section {
                DetailRow(label: "Date anniversaire", value: contract.anniversaryDate.formatted(date: .long, time: .omitted))
                DetailRow(label: "Délai de préavis", value: contract.cancellationNoticeMonths == 0 ? "Aucun délai" : "\(contract.cancellationNoticeMonths) mois avant")
            } header: {
                Text("Échéance")
                    .foregroundColor(.purple)
            }
            Section {
                DetailRow(label: "Type", value: contract.amountType.label)
                if contract.amount > 0 {
                    DetailRow(label: "Montant", value: String(format: "%.2f %@", contract.amount, contract.amountType.unit))
                }
            }  header: {
                Text("Montant")
                    .foregroundColor(.purple)
            }
            if !contract.annualAmounts.isEmpty {
                Section {
                    ForEach(contract.annualAmounts.indices, id: \.self) { index in
                        DetailRow(label: "Année \(index + 1)", value: String(format: "%.2f €", contract.annualAmounts[index]))
                    }
                }  header: {
                    Text("Montant")
                        .foregroundColor(.purple)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingEditor = true
                } label: {
                    Image(systemName: "pencil")
                        .foregroundColor(.green)
                }
                .accessibilityLabel("Modifier le contrat")
            }
        }
        .alert("Partage indisponible", isPresented: $showingShareUnavailableAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Le partage nécessite un groupe et la configuration CloudKit dans Xcode.")
        }
        .alert("Erreur de partage", isPresented: $showingShareError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(shareErrorMessage)
        }
        .sheet(isPresented: $showingEditor) {
            ContractEditorView(contract: contract, groupNames: store.groupNames) { updatedContract in
                if updatedContract.groupName.trimmingCharacters(in: .whitespacesAndNewlines) != trimmedGroupName,
                   CloudKitSharingManager.shared.isGroupShared(trimmedGroupName) {
                    // A shared contract must not be moved to another group.
                    showingShareUnavailableAlert = true
                    return
                }
                store.update(updatedContract)
                showingEditor = false
            }
        }
    }

    private func shareGroup() {
        guard !trimmedGroupName.isEmpty,
              let viewController = UIApplication.shared.firstKeyWindowRootViewController else {
            showingShareUnavailableAlert = true
            return
        }
        CloudKitSharingManager.shared.shareGroup(
            named: trimmedGroupName,
            contracts: store.contracts,
            presenting: viewController
        ) { error in
            guard let error else { return }
            shareErrorMessage = error.localizedDescription
            showingShareError = true
        }
    }
}

private struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct SummaryCard: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .foregroundColor(.accentColor)
            Text(value)
                .font(.title.bold())
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(store: PreviewData.contractStore)
    }
}

private extension UIApplication {
    var firstKeyWindowRootViewController: UIViewController? {
        guard let window = connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow),
              let rootViewController = window.rootViewController else {
            return nil
        }

        var viewController = rootViewController
        while let presented = viewController.presentedViewController {
            viewController = presented
        }
        if let navigationController = viewController as? UINavigationController,
           let visibleViewController = navigationController.visibleViewController {
            viewController = visibleViewController
        }
        return viewController
    }
}
