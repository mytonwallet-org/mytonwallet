
import Testing
import WalletContext
@testable import WalletCore

private struct SendFailed: Error {}

@Suite("SdkActivationRelay")
struct SdkActivationRelayTests {

    @Test
    func `retries failed sends until success`() async throws {
        let attempts = UnfairLock<Int>(initialState: 0)
        let relay = SdkActivationRelay(retryDelays: [.milliseconds(5), .milliseconds(5)]) { _ in
            let attempt = attempts.withLock { attempt in
                attempt += 1
                return attempt
            }
            if attempt < 3 {
                throw SendFailed()
            }
        }

        relay.requestActivation(accountId: "0-mainnet")

        try await waitUntil { attempts.withLock { $0 } == 3 }
    }

    @Test
    func `gives up once retries are exhausted`() async throws {
        let attempts = UnfairLock<Int>(initialState: 0)
        let relay = SdkActivationRelay(retryDelays: [.milliseconds(5), .milliseconds(5)]) { _ in
            attempts.withLock { $0 += 1 }
            throw SendFailed()
        }

        relay.requestActivation(accountId: "0-mainnet")

        try await waitUntil { attempts.withLock { $0 } == 3 }
        try await Task.sleep(for: .milliseconds(50))
        #expect(attempts.withLock { $0 } == 3)
    }

    @Test
    func `newer request supersedes pending retries`() async throws {
        let sent = UnfairLock<[String]>(initialState: [])
        let relay = SdkActivationRelay(retryDelays: [.seconds(60)]) { accountId in
            sent.withLock { $0.append(accountId) }
            if accountId == "0-mainnet" {
                throw SendFailed()
            }
        }

        relay.requestActivation(accountId: "0-mainnet")
        try await waitUntil { sent.withLock { $0 } == ["0-mainnet"] }

        relay.requestActivation(accountId: "1-mainnet")

        try await waitUntil { sent.withLock { $0 } == ["0-mainnet", "1-mainnet"] }
    }

    @Test
    func `cancel stops pending retries`() async throws {
        let attempts = UnfairLock<Int>(initialState: 0)
        let relay = SdkActivationRelay(retryDelays: [.milliseconds(20)]) { _ in
            attempts.withLock { $0 += 1 }
            throw SendFailed()
        }

        relay.requestActivation(accountId: "0-mainnet")
        try await waitUntil { attempts.withLock { $0 } == 1 }

        relay.cancel()

        try await Task.sleep(for: .milliseconds(100))
        #expect(attempts.withLock { $0 } == 1)
    }
}

/// Counts the timeout in 5 ms samples rather than wall time. On a loaded machine the relay's task and this wait share
/// a starved cooperative pool, and the time neither of them runs is not the condition's to spend. Ten times the
/// timeout in wall time still ends a wait whose samples keep stalling.
private func waitUntil(
    timeout: Duration = .seconds(5),
    _ condition: @Sendable () -> Bool
) async throws {
    let sampleInterval = Duration.milliseconds(5)
    var remainingSamples = Int((timeout / sampleInterval).rounded(.up))
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout * 10)
    while remainingSamples > 0, clock.now < deadline {
        if condition() {
            return
        }
        remainingSamples -= 1
        try await Task.sleep(for: sampleInterval)
    }
    #expect(condition(), "timed out waiting for condition")
}
