import Testing

/// Runs the suites that point the shared `SettingsStore` at a database of their own one at a time. Swift Testing runs
/// suites in parallel and these interleave on the main actor at every `await`, so one suite's fixture would reset the
/// settings another suite is checking, or drop the database a pending write still needs.
struct SettingsStoreIsolation: SuiteTrait, TestScoping {
    private static let gate = Gate()

    func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: @concurrent @Sendable () async throws -> Void
    ) async throws {
        await Self.gate.acquire()
        do {
            try await function()
        } catch {
            await Self.gate.release()
            throw error
        }
        await Self.gate.release()
    }

    private actor Gate {
        private var isHeld = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func acquire() async {
            guard isHeld else {
                isHeld = true
                return
            }
            await withCheckedContinuation { waiters.append($0) }
        }

        func release() {
            if waiters.isEmpty {
                isHeld = false
            } else {
                waiters.removeFirst().resume()
            }
        }
    }
}

extension Trait where Self == SettingsStoreIsolation {
    static var settingsStoreIsolation: Self { Self() }
}
