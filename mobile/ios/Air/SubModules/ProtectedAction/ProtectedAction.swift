import SwiftUI
import WalletCore

@MainActor
public protocol ConfirmationContent: View {
    associatedtype CompactRepresentation: View

    @ViewBuilder var compactRepresentation: CompactRepresentation { get }
}

@MainActor
public struct ProtectedAction<HeaderView: ConfirmationContent, Result: MfaProtectedActionResult> {
    public let account: MAccount
    public let software: SoftwareOperation<Result>
    public let hardware: (() async throws -> HardwareOperation<Result>)?
    public let confirmation: Confirmation<HeaderView>
    public let completion: Completion<Result>

    public init(
        account: MAccount,
        software: SoftwareOperation<Result>,
        hardware: (() async throws -> HardwareOperation<Result>)?,
        confirmation: Confirmation<HeaderView>,
        completion: Completion<Result> = .dismissAuthorization
    ) {
        self.account = account
        self.software = software
        self.hardware = hardware
        self.confirmation = confirmation
        self.completion = completion
    }

    public init(
        account: MAccount,
        software: SoftwareOperation<Result>,
        hardware: HardwareOperation<Result>,
        confirmation: Confirmation<HeaderView>,
        completion: Completion<Result> = .dismissAuthorization
    ) {
        self.account = account
        self.software = software
        self.hardware = { hardware }
        self.confirmation = confirmation
        self.completion = completion
    }
}

@MainActor
public struct Confirmation<HeaderView: ConfirmationContent> {
    public let title: String
    public let headerView: HeaderView
    public let presentationStyle: PresentationStyle
    public let biometricPolicy: BiometricPolicy
    public let prefersNavigationTitleWithCustomHeader: Bool

    public init(
        title: String,
        header: HeaderView,
        presentationStyle: PresentationStyle = .push,
        biometricPolicy: BiometricPolicy = .onAuthorizationScreen,
        prefersNavigationTitleWithCustomHeader: Bool = true
    ) {
        self.title = title
        self.headerView = header
        self.presentationStyle = presentationStyle
        self.biometricPolicy = biometricPolicy
        self.prefersNavigationTitleWithCustomHeader = prefersNavigationTitleWithCustomHeader
    }
}

public enum BiometricPolicy: Sendable, Equatable {
    case onAuthorizationScreen
    case beforePresentation
    case disabled
}

public enum ActivitySource: Hashable, Sendable {
    case local
    case pendingOrConfirmed
}

@MainActor
public struct ActivityCompletion<Result: MfaProtectedActionResult> {
    public let sources: Set<ActivitySource>
    public let timeout: Duration
    public let context: ActivityDetailsContext
    /// Exact correlation that may consume an activity observed before the latest submission step.
    public let matches: (ApiActivity, ActionSubmissionReceipt<Result>) -> Bool
    /// Heuristic correlation, restricted to activities observed after the latest submission step began.
    public let fallbackMatches: ((ApiActivity, ActionSubmissionReceipt<Result>) -> Bool)?

    public init(
        sources: Set<ActivitySource> = [.local],
        timeout: Duration = .seconds(10),
        context: ActivityDetailsContext,
        matches: @escaping (ApiActivity, ActionSubmissionReceipt<Result>) -> Bool,
        fallbackMatches: ((ApiActivity, ActionSubmissionReceipt<Result>) -> Bool)? = nil
    ) {
        self.sources = sources
        self.timeout = timeout
        self.context = context
        self.matches = matches
        self.fallbackMatches = fallbackMatches
    }
}

@MainActor
public enum Completion<Result: MfaProtectedActionResult> {
    case dismissAuthorization
    case finish((ActionSubmissionReceipt<Result>) -> Void)
    case handoff((ActionSubmissionReceipt<Result>) -> Void)
    case replace((ActionSubmissionReceipt<Result>) -> Replacement?)
    case activity(ActivityCompletion<Result>)
}

@MainActor
public enum Outcome<Result: MfaProtectedActionResult> {
    case completed(ActionSubmissionReceipt<Result>)
    case partiallyCommitted(
        receipt: ActionSubmissionReceipt<Result>,
        remainingWork: ActionRemainingWork
    )
    case indeterminate(error: any Error, receipt: ActionSubmissionReceipt<Result>?)
    case cancelled
    case failed(any Error)
}

public enum PresentationStyle: Sendable {
    case push
    case sheet
}
