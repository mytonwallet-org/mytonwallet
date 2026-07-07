import AppIntents
import WalletCoreTypes

@available(iOS 18.4, *)
public struct OpenTokenIntent: OpenIntent {
    public static let title: LocalizedStringResource = "Open Token"
    public static let description = IntentDescription("Open the token screen.")
    public static let openAppWhenRun = true

    @available(iOS 26.0, *)
    public static var supportedModes: IntentModes {
        .foreground(.immediate)
    }

    @Parameter(title: LocalizedStringResource("Token"))
    public var target: TokenEntity

    @Parameter(title: LocalizedStringResource("Account"))
    public var account: AccountEntity?

    public init() {}

    public init(target: TokenEntity, account: AccountEntity? = nil) {
        self.target = target
        self.account = account
    }

    @MainActor
    public func perform() async throws -> some IntentResult {
        guard AirLauncher.isOnTheAir else {
            return .result()
        }
        AirLauncher.handle(systemAction: .openToken(accountId: account?.id, tokenSlug: target.tokenSlug))
        return .result()
    }
}
