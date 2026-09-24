import UIKit
import WalletContext
import WalletCore

@MainActor
final class HomeAccountTransition<Presentation> {
    private(set) var displayedAccountId: String?
    private var pendingAccountId: String?
    private var task: Task<Void, Never>?

    func request(
        accountId: String,
        prepare: @escaping @MainActor () async -> Presentation?,
        commit: @escaping @MainActor (Presentation) -> Void
    ) {
        guard pendingAccountId != accountId else { return }
        task?.cancel()
        task = nil
        pendingAccountId = nil
        guard displayedAccountId != accountId else { return }
        pendingAccountId = accountId
        task = Task { [weak self] in
            let presentation = await prepare()
            guard !Task.isCancelled, let self else { return }
            self.pendingAccountId = nil
            self.task = nil
            guard let presentation else { return }
            self.displayedAccountId = accountId
            commit(presentation)
        }
    }

    isolated deinit {
        task?.cancel()
    }
}
