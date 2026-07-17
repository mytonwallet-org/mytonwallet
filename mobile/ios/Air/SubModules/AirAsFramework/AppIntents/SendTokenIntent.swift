import AppIntents
import WalletCoreTypes

@available(iOS 18.4, *)
public struct SendTokenIntent: AppIntent {
    public static let title: LocalizedStringResource = "Send Token"
    public static let description = IntentDescription("Open the send screen.")
    public static let openAppWhenRun = true

    @available(iOS 26.0, *)
    public static var supportedModes: IntentModes {
        .foreground(.immediate)
    }

    @Parameter(title: LocalizedStringResource("Sender"))
    public var sender: AccountEntity?

    @Parameter(title: LocalizedStringResource("Recipient"), query: SendTokenRecipientEntityQuery())
    public var recipient: RecipientEntity?

    @Parameter(title: LocalizedStringResource("Amount"))
    public var amount: Double?

    @Parameter(title: LocalizedStringResource("Token"))
    public var token: TokenEntity?

    @Parameter(title: LocalizedStringResource("Comment"))
    public var comment: String?

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        AirLauncher.handle(systemAction: .sendToken(
            accountId: sender?.id,
            recipient: recipient?.systemRecipient,
            tokenSlug: token?.tokenSlug,
            amount: amount,
            comment: comment
        ))
        return .result()
    }
}
