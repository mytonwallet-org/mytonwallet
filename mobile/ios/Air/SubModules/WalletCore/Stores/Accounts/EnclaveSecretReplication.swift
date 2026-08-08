import NativeEnclave

enum EnclaveSecretReplication {
    static func importSecret(
        accountIds: [String],
        importPrimary: (String) async throws -> Void,
        duplicate: (String, String) async throws -> Void,
        existingIds: (Set<String>) async throws -> Set<String>
    ) async throws {
        let expectedIds = Set(accountIds)
        guard let primaryId = accountIds.first,
              expectedIds.count == accountIds.count else {
            throw EnclaveError.malformedEncryptedPayload
        }

        try await importPrimary(primaryId)
        for accountId in accountIds.dropFirst() {
            try await duplicate(primaryId, accountId)
        }
        try await verify(expectedIds: expectedIds, existingIds: existingIds)
    }

    static func duplicateSecret(
        from sourceId: String,
        to targetIds: [String],
        duplicate: (String, String) async throws -> Void,
        existingIds: (Set<String>) async throws -> Set<String>
    ) async throws {
        let expectedIds = Set(targetIds)
        guard expectedIds.count == targetIds.count,
              !expectedIds.contains(sourceId) else {
            throw EnclaveError.malformedEncryptedPayload
        }

        for targetId in targetIds {
            try await duplicate(sourceId, targetId)
        }
        try await verify(expectedIds: expectedIds, existingIds: existingIds)
    }

    private static func verify(
        expectedIds: Set<String>,
        existingIds: (Set<String>) async throws -> Set<String>
    ) async throws {
        guard try await existingIds(expectedIds) == expectedIds else {
            throw EnclaveError.malformedEncryptedPayload
        }
    }
}
