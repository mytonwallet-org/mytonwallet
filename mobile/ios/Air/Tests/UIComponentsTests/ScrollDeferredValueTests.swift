import Testing
@testable import UIComponents

@Suite("Home card balance updates during scrolling")
struct ScrollDeferredValueTests {
    @Test func coalescesUpdatesUntilDecelerationEnds() {
        var value = ScrollDeferredValue<Int?>(100)
        for update in [120, 140, 170] {
            let changed = value.update(update, isScrolling: true)
            #expect(!changed)
            #expect(value.displayed == 100)
        }
        let flushed = value.update(value.latest, isScrolling: false)
        #expect(flushed)
        #expect(value.displayed == 170)
        let repeated = value.update(value.latest, isScrolling: false)
        #expect(!repeated)
    }

    @Test func retainsLoadingAndCurrencyResetStates() {
        var value = ScrollDeferredValue<Int?>(100)
        let deferred = value.update(nil, isScrolling: true)
        #expect(!deferred)
        let flushed = value.update(value.latest, isScrolling: false)
        #expect(flushed)
        #expect(value.displayed == nil)
        let loaded = value.update(250, isScrolling: false)
        #expect(loaded)
        #expect(value.displayed == 250)
    }

    @Test func doesNotReplayIntermediateOrUnchangedValues() {
        var value = ScrollDeferredValue(100)
        let intermediate = value.update(200, isScrolling: true)
        #expect(!intermediate)
        let original = value.update(100, isScrolling: true)
        #expect(!original)
        let flushed = value.update(value.latest, isScrolling: false)
        #expect(!flushed)
        #expect(value.displayed == 100)
    }
}
