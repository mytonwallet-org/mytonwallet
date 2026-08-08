import UIKit
import WalletCore

@MainActor
public protocol ProtectedActionExecuting {
    static func execute<HeaderView: ConfirmationContent, Result: MfaProtectedActionResult>(
        _ action: ProtectedAction<HeaderView, Result>,
        in context: ExecutionContext
    ) async -> Outcome<Result>
}

public extension ProtectedActionExecuting {
    static func execute<HeaderView: ConfirmationContent, Result: MfaProtectedActionResult>(
        _ action: ProtectedAction<HeaderView, Result>,
        on viewController: UIViewController
    ) async -> Outcome<Result> {
        await execute(action, in: ExecutionContext(viewController))
    }
}

@MainActor
public var ProtectedActionExecutor: any ProtectedActionExecuting.Type = UnconfiguredProtectedActionExecutor.self

private enum UnconfiguredProtectedActionExecutor: ProtectedActionExecuting {
    static func execute<HeaderView: ConfirmationContent, Result: MfaProtectedActionResult>(
        _ action: ProtectedAction<HeaderView, Result>,
        in context: ExecutionContext
    ) async -> Outcome<Result> {
        assertionFailure("ProtectedActionExecutor has not been configured")
        return .failed(UnconfiguredProtectedActionExecutorError())
    }
}

private struct UnconfiguredProtectedActionExecutorError: Error, LocalizedError {
    var errorDescription: String? {
        "Protected action executor is not configured"
    }
}
