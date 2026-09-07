import Foundation
import Testing
@testable import WalletContext

@Suite("Log File Storage")
struct LogFileStorageTests {
    @Test
    func `line aligned tail drops a partial UTF-8 row`() throws {
        let data = Data("old row\nemoji 🙂 row\nnewest row\n".utf8)
        let maximumByteCount = Data("i 🙂 row\nnewest row\n".utf8).count

        let tail = LogFileStorage.lineAlignedTail(
            of: data,
            maximumByteCount: maximumByteCount
        )

        #expect(String(decoding: tail, as: UTF8.self) == "newest row\n")
    }
}
