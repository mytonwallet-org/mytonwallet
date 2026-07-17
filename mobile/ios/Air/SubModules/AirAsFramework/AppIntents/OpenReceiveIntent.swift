import AppIntents
import WalletCoreTypes

@available(iOS 18.4, *)
public struct OpenReceiveIntent: AppIntent {
    public static let title: LocalizedStringResource = "Receive Funds"
    public static let description = IntentDescription("Open the receive screen.")
    public static let openAppWhenRun = true

    @available(iOS 26.0, *)
    public static var supportedModes: IntentModes {
        .foreground(.immediate)
    }

    @Parameter(title: LocalizedStringResource("Account"))
    public var account: AccountEntity?

    @Parameter(title: LocalizedStringResource("Network"))
    public var chain: ChainEntity?

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        AirLauncher.handle(systemAction: .openReceive(accountId: account?.id, chain: chain?.id))
        return .result()
    }
}
