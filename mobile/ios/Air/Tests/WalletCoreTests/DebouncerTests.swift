
import Testing
import WalletContext
@testable import WalletCore

@Suite("Debouncer")
struct DebouncerTests {

    @Test
    func `runs the operation after the delay`() async throws {
        let runs = UnfairLock<Int>(initialState: 0)
        let debouncer = Debouncer(delay: .milliseconds(20))

        debouncer.schedule {
            runs.withLock { $0 += 1 }
        }
        #expect(runs.withLock { $0 } == 0)

        try await waitUntil { runs.withLock { $0 } == 1 }
    }

    @Test
    func `a burst of schedules runs only the last operation`() async throws {
        let ran = UnfairLock<[String]>(initialState: [])
        let debouncer = Debouncer(delay: .milliseconds(20))

        for id in ["a", "b", "c"] {
            debouncer.schedule {
                ran.withLock { $0.append(id) }
            }
        }

        try await waitUntil { !ran.withLock { $0 }.isEmpty }
        try await Task.sleep(for: .milliseconds(100))
        #expect(ran.withLock { $0 } == ["c"])
    }

    @Test
    func `cancel prevents the pending operation from running`() async throws {
        let runs = UnfairLock<Int>(initialState: 0)
        let debouncer = Debouncer(delay: .milliseconds(20))

        debouncer.schedule {
            runs.withLock { $0 += 1 }
        }
        debouncer.cancel()

        try await Task.sleep(for: .milliseconds(100))
        #expect(runs.withLock { $0 } == 0)
    }
}

private func waitUntil(
    timeout: Duration = .seconds(5),
    _ condition: @Sendable () -> Bool
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while clock.now < deadline {
        if condition() {
            return
        }
        try await Task.sleep(for: .milliseconds(5))
    }
    #expect(condition(), "timed out waiting for condition")
}
