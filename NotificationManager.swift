import Foundation
import UserNotifications
import UIKit

@MainActor
final class NotificationManager: ObservableObject {
    static let shared = NotificationManager()

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private let center = UNUserNotificationCenter.current()

    private init() {
        refreshAuthorizationStatus()
    }

    func refreshAuthorizationStatus() {
        center.getNotificationSettings { [weak self] settings in
            Task { @MainActor in
                self?.authorizationStatus = settings.authorizationStatus
            }
        }
    }

    func requestAuthorization() async {
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            // The user can try again from the notification management screen.
        }
        refreshAuthorizationStatus()
    }

    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    func scheduleNotification(for contract: Contract) {
        cancelNotification(for: contract)
        guard contract.status != "Résilié", let alertDate = nextAlertDate(for: contract) else { return }

        let content = UNMutableNotificationContent()
        content.title = "Échéance de contrat"
        content.body = "Le préavis de « \(contract.name) » arrive bientôt."
        content.sound = .default

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: alertDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: notificationIdentifier(for: contract),
            content: content,
            trigger: trigger
        )
        center.add(request)
    }

    func cancelNotification(for contract: Contract) {
        center.removePendingNotificationRequests(
            withIdentifiers: [notificationIdentifier(for: contract)]
        )
    }

    private func notificationIdentifier(for contract: Contract) -> String {
        "contract-\(contract.id.uuidString)"
    }

    private func nextAlertDate(for contract: Contract) -> Date? {
        let calendar = Calendar.current
        let now = Date()
        let anniversaryComponents = calendar.dateComponents([.month, .day], from: contract.anniversaryDate)
        guard let month = anniversaryComponents.month, let day = anniversaryComponents.day else { return nil }

        let currentYear = calendar.component(.year, from: now)
        for year in [currentYear, currentYear + 1] {
            guard let anniversary = calendar.date(from: DateComponents(year: year, month: month, day: day)),
                  let alertDate = calendar.date(
                    byAdding: .month,
                    value: -(contract.cancellationNoticeMonths + 1),
                    to: anniversary
                  ) else { continue }

            var components = calendar.dateComponents([.year, .month, .day], from: alertDate)
            components.hour = 9
            components.minute = 0
            if let normalizedDate = calendar.date(from: components), normalizedDate > now {
                return normalizedDate
            }
        }
        return nil
    }
}

extension UNAuthorizationStatus {
    var frenchDescription: String {
        switch self {
        case .notDetermined: return "Autorisation non demandée"
        case .denied: return "Notifications désactivées"
        case .authorized: return "Notifications activées"
        case .provisional: return "Notifications activées provisoirement"
        case .ephemeral: return "Notifications temporaires"
        @unknown default: return "État inconnu"
        }
    }
}
