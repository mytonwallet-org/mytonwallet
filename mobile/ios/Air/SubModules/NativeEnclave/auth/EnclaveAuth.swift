import Foundation

protocol EnclaveAuth {
    nonisolated(nonsending) func setup(masterKey: Data, passcode: String?) async throws
    nonisolated(nonsending) func authorize(passcode: String?) async throws -> Data
    nonisolated(nonsending) func destroy() async
}
