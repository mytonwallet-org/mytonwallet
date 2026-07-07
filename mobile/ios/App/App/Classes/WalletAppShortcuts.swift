import AirAsFramework
import AppIntents

@available(iOS 18.4, *)
struct WalletAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SendTokenIntent(),
            phrases: [
                "Send token with \(.applicationName)",
                "Send crypto with \(.applicationName)",
                "Open send in \(.applicationName)",
            ],
            shortTitle: "Send",
            systemImageName: "arrow.up.circle.fill"
        )

        AppShortcut(
            intent: OpenReceiveIntent(),
            phrases: [
                "Receive with \(.applicationName)",
                "Add crypto with \(.applicationName)",
                "Open receive in \(.applicationName)",
            ],
            shortTitle: "Receive",
            systemImageName: "arrow.down.circle.fill"
        )

        AppShortcut(
            intent: OpenTokenIntent(),
            phrases: [
                "Open \(\.$target) in \(.applicationName)",
                "Show \(\.$target) in \(.applicationName)",
            ],
            shortTitle: "Open Token",
            systemImageName: "chart.line.uptrend.xyaxis.circle.fill"
        )

        AppShortcut(
            intent: ScanQRCodeIntent(),
            phrases: [
                "Scan QR with \(.applicationName)",
                "Scan a code with \(.applicationName)",
                "Open scanner in \(.applicationName)",
            ],
            shortTitle: "Scan QR",
            systemImageName: "viewfinder.circle.fill"
        )
    }
}
