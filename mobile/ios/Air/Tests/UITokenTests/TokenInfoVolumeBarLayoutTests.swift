import Testing
@testable import UIToken

@Suite("Token Info Volume Bar Layout")
struct TokenInfoVolumeBarLayoutTests {
    @Test
    func `zero values split the bar evenly`() {
        let layout = TokenInfoVolumeBarLayout.resolve(
            buy: 0,
            sell: 0,
            width: 320,
            buyLabelWidth: 14,
            sellLabelWidth: 14
        )

        #expect(layout.buyWidth == 158)
        #expect(layout.sellWidth == 158)
        #expect(layout.spacing == 4)
    }

    @Test
    func `zero buy volume omits its segment`() {
        let layout = TokenInfoVolumeBarLayout.resolve(
            buy: 0,
            sell: 100,
            width: 320,
            buyLabelWidth: 14,
            sellLabelWidth: 32
        )

        #expect(layout.buyWidth == nil)
        #expect(layout.sellWidth == 320)
        #expect(layout.spacing == 0)
    }

    @Test
    func `zero sell volume omits its segment`() {
        let layout = TokenInfoVolumeBarLayout.resolve(
            buy: 100,
            sell: 0,
            width: 320,
            buyLabelWidth: 32,
            sellLabelWidth: 14
        )

        #expect(layout.buyWidth == 320)
        #expect(layout.sellWidth == nil)
        #expect(layout.spacing == 0)
    }

    @Test
    func `smaller segment expands enough to fit its label`() {
        let layout = TokenInfoVolumeBarLayout.resolve(
            buy: 999,
            sell: 1,
            width: 320,
            buyLabelWidth: 42,
            sellLabelWidth: 32
        )

        #expect(layout.buyWidth == 268)
        #expect(layout.sellWidth == 48)
        #expect(layout.spacing == 4)
    }

    @Test
    func `ratio stays exact when both labels already fit`() {
        let layout = TokenInfoVolumeBarLayout.resolve(
            buy: 75,
            sell: 25,
            width: 324,
            buyLabelWidth: 32,
            sellLabelWidth: 32
        )

        #expect(layout.buyWidth == 240)
        #expect(layout.sellWidth == 80)
        #expect(layout.spacing == 4)
    }
}
