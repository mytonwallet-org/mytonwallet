import WalletCore

@MainActor
public struct HardwareOperationContext {
    private let progressHandler: @MainActor (_ completedUnitCount: Int, _ totalUnitCount: Int) -> Void

    public init(
        progressHandler: @escaping @MainActor (_ completedUnitCount: Int, _ totalUnitCount: Int) -> Void
    ) {
        self.progressHandler = progressHandler
    }

    public func updateProgress(completedUnitCount: Int, totalUnitCount: Int) {
        progressHandler(completedUnitCount, totalUnitCount)
    }
}

@MainActor
public struct HardwareOperation<Payload: Sendable> {
    private let performOperation: @MainActor (
        HardwareOperationContext
    ) async -> ActionSubmissionResult<Payload>

    public static func single(
        _ submit: @escaping @MainActor () async throws -> ActionSubmissionReceipt<Payload>
    ) -> Self {
        Self { _ in
            do {
                return .committed(try await submit())
            } catch {
                return actionSubmissionFailure(for: error)
            }
        }
    }

    public static func custom(
        _ perform: @escaping @MainActor (
            HardwareOperationContext
        ) async -> ActionSubmissionResult<Payload>
    ) -> Self {
        Self(perform: perform)
    }

    private init(
        perform: @escaping @MainActor (
            HardwareOperationContext
        ) async -> ActionSubmissionResult<Payload>
    ) {
        self.performOperation = perform
    }

    public func perform(
        context: HardwareOperationContext
    ) async -> ActionSubmissionResult<Payload> {
        await performOperation(context)
    }
}
