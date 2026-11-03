import XCTest
@testable import WalletContext

final class AudioHelpersTests: XCTestCase {
    @MainActor
    func testNestedSoundSuspensionsSuppressPlaybackUntilEveryOwnerReleases() {
        var playbackCount = 0
        let playback: (AudioHelpers.Sound) -> Void = { _ in playbackCount += 1 }

        AudioHelpers.play(sound: .incomingTransaction, using: playback)
        XCTAssertEqual(playbackCount, 1)

        let resumeFirst = AudioHelpers.suspendSounds()
        defer { resumeFirst() }
        AudioHelpers.play(sound: .incomingTransaction, using: playback)
        XCTAssertEqual(playbackCount, 1)

        let resumeSecond = AudioHelpers.suspendSounds()
        defer { resumeSecond() }
        AudioHelpers.play(sound: .incomingTransaction, using: playback)
        XCTAssertEqual(playbackCount, 1)

        resumeFirst()
        resumeFirst()
        AudioHelpers.play(sound: .incomingTransaction, using: playback)
        XCTAssertEqual(playbackCount, 1)

        resumeSecond()
        AudioHelpers.play(sound: .incomingTransaction, using: playback)
        XCTAssertEqual(playbackCount, 2)
    }
}
