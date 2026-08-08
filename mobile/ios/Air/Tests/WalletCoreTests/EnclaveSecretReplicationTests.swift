import NativeEnclave
import Testing
@testable import WalletCore

@Suite("Enclave Secret Replication")
struct EnclaveSecretReplicationTests {
    @Test
    func `imports once and duplicates to remaining accounts`() async throws {
        let recorder = Recorder()

        try await EnclaveSecretReplication.importSecret(
            accountIds: ["primary", "second", "third"],
            importPrimary: { accountId in
                recorder.importedIds.append(accountId)
                recorder.existingIds.insert(accountId)
            },
            duplicate: { sourceId, targetId in
                recorder.duplicates.append((sourceId, targetId))
                recorder.existingIds.insert(targetId)
            },
            existingIds: { _ in recorder.existingIds }
        )

        #expect(recorder.importedIds == ["primary"])
        #expect(recorder.duplicates.map { $0.0 } == ["primary", "primary"])
        #expect(recorder.duplicates.map { $0.1 } == ["second", "third"])
    }

    @Test
    func `fails when a replicated secret is missing`() async {
        await #expect(throws: EnclaveError.self) {
            try await EnclaveSecretReplication.duplicateSecret(
                from: "source",
                to: ["target"],
                duplicate: { _, _ in },
                existingIds: { _ in [] }
            )
        }
    }

    @Test
    func `rejects duplicate account ids before importing`() async {
        let recorder = Recorder()

        await #expect(throws: EnclaveError.self) {
            try await EnclaveSecretReplication.importSecret(
                accountIds: ["same", "same"],
                importPrimary: { accountId in
                    recorder.importedIds.append(accountId)
                },
                duplicate: { _, _ in },
                existingIds: { _ in [] }
            )
        }

        #expect(recorder.importedIds.isEmpty)
    }
}

private final class Recorder {
    var importedIds: [String] = []
    var duplicates: [(String, String)] = []
    var existingIds: Set<String> = []
}
