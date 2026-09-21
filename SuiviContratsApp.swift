import SwiftUI

extension Color {
    static let appBackground = Color(
        red: 254.3 / 255.0,
        green: 248.0 / 255.0,
        blue: 231.0 / 255.0
    )

    static let appBrown = Color(
        red: 74.0 / 255.0,
        green: 50.0 / 255.0,
        blue: 4.0 / 255.0
    )

    static let appDarkGreen = Color(
        red: 0.0,
        green: 78.0 / 255.0,
        blue: 77.0 / 255.0
    )
}

@main
struct SuiviContratsApp: App {
    @StateObject private var store: ContractStore

    init() {
        let store = ContractStore()
        _store = StateObject(wrappedValue: store)
    }

    var body: some Scene {
        WindowGroup {
            AppLaunchView(store: store)
        }
    }
}
