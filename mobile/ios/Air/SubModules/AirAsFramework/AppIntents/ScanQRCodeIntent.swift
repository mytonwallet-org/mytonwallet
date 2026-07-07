import AppIntents

@available(iOS 18.4, *)
public struct ScanQRCodeIntent: AppIntent {
    public static let title: LocalizedStringResource = "Scan QR Code"
    public static let description = IntentDescription("Open the QR scanner.")
    public static let openAppWhenRun = true

    @available(iOS 26.0, *)
    public static var supportedModes: IntentModes {
        .foreground(.immediate)
    }

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        guard AirLauncher.isOnTheAir else {
            return .result()
        }
        AirLauncher.handle(systemAction: .scanQR)
        return .result()
    }
}
