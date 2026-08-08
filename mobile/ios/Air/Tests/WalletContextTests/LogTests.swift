import Testing
@testable import WalletContext

@Suite("Log fault reporting", .serialized)
struct LogTests {
    @Test
    func `forwards fault-level events with source context`() async {
        let events = UnfairLock(initialState: [LogFaultEvent]())
        Log.setFaultReporter { event in
            events.withLock { $0.append(event) }
        }
        defer { Log.setFaultReporter(nil) }

        let log = Log("FaultReporterTest")
        log.error(
            "ordinary error",
            fileID: "WalletContextTests/LogTests.swift",
            function: "test()",
            line: 40
        )
        log.fault(
            "programmer error 42",
            fileID: "WalletContextTests/LogTests.swift",
            function: "test()",
            line: 41
        )
        await log.critical(
            "synchronously persisted fault",
            fileID: "WalletContextTests/LogTests.swift",
            function: "test()",
            line: 42
        )

        let matchingEvents = events.withLock {
            $0.filter { $0.category == "FaultReporterTest" }
        }
        #expect(matchingEvents.map(\.message) == [
            "programmer error 42",
            "synchronously persisted fault",
        ])
        #expect(matchingEvents.map(\.fileID) == [
            "WalletContextTests/LogTests.swift",
            "WalletContextTests/LogTests.swift",
        ])
        #expect(matchingEvents.map(\.function) == ["test()", "test()"])
        #expect(matchingEvents.map(\.line) == [41, 42])
    }

    @Test
    func `always redacts private fault values for remote reporting`() {
        let events = UnfairLock(initialState: [LogFaultEvent]())
        Log.setFaultReporter { event in
            events.withLock { $0.append(event) }
        }
        defer { Log.setFaultReporter(nil) }

        let secret = "alpha beta gamma"
        let accountId = "0-mainnet"
        Log("FaultPrivacyTest").fault(
            "secret=\(secret) account=\(accountId, .public) retry=\(2) explicit=\(7, .redacted)"
        )

        let message = events.withLock {
            $0.first { $0.category == "FaultPrivacyTest" }?.message
        }
        #expect(
            message == "secret=<redacted> account=0-mainnet retry=2 explicit=<redacted>"
        )
    }
}
