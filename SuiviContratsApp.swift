import SwiftUI

extension Color {
    static let appBackground = Color(
        red: 254.0 / 255.0,
        green: 248.0 / 255.0,
        blue: 231.0 / 255.0
    )
    static let appBrown = Color(
            red: 74 / 255,
            green: 50 / 255,
            blue: 4 / 255
        )
}

@main
struct SuiviContratsApp: App {
    var body: some Scene {
        WindowGroup {
            AppLaunchView()
        }
    }
}
