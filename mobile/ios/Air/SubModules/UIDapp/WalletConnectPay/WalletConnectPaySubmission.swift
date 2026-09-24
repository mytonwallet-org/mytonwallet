import Foundation

@MainActor
final class WalletConnectPaySubmission {
    private enum State {
        case ready, submitting, submitted
    }

    private var state = State.ready
    private var isDismissed = false
    private let onCancel: () -> Void
    private let onDismiss: () -> Void

    init(onCancel: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        self.onCancel = onCancel
        self.onDismiss = onDismiss
    }

    func submit<Result>(_ operation: () async throws -> Result) async throws -> Result {
        guard !isDismissed, state == .ready else { throw CancellationError() }
        state = .submitting
        do {
            let result = try await operation()
            state = .submitted
            return result
        } catch {
            state = .ready
            if isDismissed {
                onCancel()
            }
            throw error
        }
    }

    func dismiss() {
        guard !isDismissed else { return }
        isDismissed = true
        // Once signing starts, only a failure may cancel the SDK promise.
        if state == .ready {
            onCancel()
        }
        onDismiss()
    }
}
