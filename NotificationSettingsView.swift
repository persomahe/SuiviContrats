import SwiftUI
import UserNotifications

struct NotificationSettingsView: View {
    @ObservedObject private var notificationManager = NotificationManager.shared
    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Label(notificationManager.authorizationStatus.frenchDescription, systemImage: statusIcon)
                        .foregroundColor(statusColor)

                    if notificationManager.authorizationStatus == .denied {
                        Text("Les notifications sont désactivées dans les réglages de l’iPhone.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                        Button("Ouvrir les réglages") {
                            notificationManager.openSystemSettings()
                        }
                    } else if notificationManager.authorizationStatus == .notDetermined {
                        Button("Autoriser les notifications") {
                            Task { await notificationManager.requestAuthorization() }
                        }
                    } else {
                        Button("Actualiser l’autorisation") {
                            notificationManager.refreshAuthorizationStatus()
                        }
                    }
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("Une alerte est programmée un mois avant le délai de résiliation, avant la date anniversaire du contrat.")
                }
            }
            .navigationTitle("Gérer les notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fermer") { presentationMode.wrappedValue.dismiss() }
                }
            }
        }
        .onAppear { notificationManager.refreshAuthorizationStatus() }
    }

    private var statusIcon: String {
        switch notificationManager.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return "bell.fill"
        case .denied: return "bell.slash.fill"
        default: return "bell"
        }
    }

    private var statusColor: Color {
        switch notificationManager.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return .green
        case .denied: return .red
        default: return .orange
        }
    }
}
