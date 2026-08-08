import UIKit
import WalletContext

private let authorizationUILog = Log("ProtectedActionAuthorizationUI")

@MainActor
final class AuthorizationUI {
    typealias FeedbackPresentation = @MainActor (
        _ host: UIViewController,
        _ feedback: SubmissionFeedback
    ) async -> Bool

    enum ScreenTransitionResult {
        case unavailable
        case succeeded
        case failed
    }

    private var dismissHandler: (() -> Void)?
    private var nextScreenTransition: ((UIViewController) -> (() -> Void)?)?
    private var submissionStartedHandler: (() -> Void)?
    private var completionCancellationHandler: (() -> Void)?
    private var isCompletionCancellationPending = false
    private var didRequestCompletionCancellation = false
    private var acceptsCompletionCancellation = true
    private weak var alertHost: UIViewController?
    private weak var fallbackAlertHost: UIViewController?
    private let feedbackPresentation: FeedbackPresentation
    private var isPresentingFeedback = false
    private var didPresentFeedback = false

    init(
        fallbackAlertHost: UIViewController? = nil,
        feedbackPresentation: @escaping FeedbackPresentation = AuthorizationSupport.presentFeedbackAndWait
    ) {
        self.fallbackAlertHost = fallbackAlertHost
        self.feedbackPresentation = feedbackPresentation
    }

    func setAlertHost(_ alertHost: UIViewController) {
        guard !isPresentingFeedback, !didPresentFeedback else { return }
        self.alertHost = alertHost
    }

    func setDismissHandler(_ dismissHandler: @escaping () -> Void) {
        self.dismissHandler = dismissHandler
    }

    func setNextScreenTransition(
        _ transition: @escaping (UIViewController) -> (() -> Void)?
    ) {
        nextScreenTransition = transition
    }

    func setSubmissionStartedHandler(_ handler: @escaping () -> Void) {
        submissionStartedHandler = handler
    }

    func beginSubmission() {
        submissionStartedHandler?()
    }

    func transitionToNextScreen(
        _ viewController: UIViewController
    ) -> ScreenTransitionResult {
        guard let transition = nextScreenTransition else { return .unavailable }
        nextScreenTransition = nil
        guard let dismissHandler = transition(viewController) else { return .failed }
        self.dismissHandler = dismissHandler
        return .succeeded
    }

    func setCompletionCancellationHandler(_ handler: @escaping () -> Void) {
        guard acceptsCompletionCancellation else { return }
        completionCancellationHandler = handler
        if isCompletionCancellationPending {
            isCompletionCancellationPending = false
            handler()
        }
    }

    func requestCompletionCancellation() {
        guard acceptsCompletionCancellation, !didRequestCompletionCancellation else { return }
        didRequestCompletionCancellation = true
        if let completionCancellationHandler {
            completionCancellationHandler()
        } else {
            isCompletionCancellationPending = true
        }
    }

    func beginCompletionPresentation() {
        stopAcceptingCompletionCancellation()
    }

    @discardableResult
    func present(_ feedback: SubmissionFeedback) async -> Bool {
        guard !isPresentingFeedback, !didPresentFeedback else { return false }
        isPresentingFeedback = true
        didPresentFeedback = true
        beginCompletionPresentation()
        defer { isPresentingFeedback = false }

        var seenHosts = Set<ObjectIdentifier>()
        let hosts = [alertHost, fallbackAlertHost].compactMap { $0 }
        for host in hosts where seenHosts.insert(ObjectIdentifier(host)).inserted {
            if await feedbackPresentation(host, feedback) {
                return true
            }
        }
        authorizationUILog.fault("Protected action feedback presenter is unavailable")
        return false
    }

    func dismiss() {
        let dismissHandler = dismissHandler
        self.dismissHandler = nil
        stopAcceptingCompletionCancellation()
        dismissHandler?()
        submissionStartedHandler = nil
        alertHost = nil
        fallbackAlertHost = nil
    }

    func clear() {
        dismissHandler = nil
        submissionStartedHandler = nil
        stopAcceptingCompletionCancellation()
        alertHost = nil
        fallbackAlertHost = nil
    }

    private func stopAcceptingCompletionCancellation() {
        nextScreenTransition = nil
        acceptsCompletionCancellation = false
        completionCancellationHandler = nil
        isCompletionCancellationPending = false
    }
}
