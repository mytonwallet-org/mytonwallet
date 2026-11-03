import Testing
@testable import AirAsFramework

struct PerpsInitialLoadingTests {
    @Test func refreshesCannotDimValuesThatWereAlreadyPresentedFresh() {
        var presentation = PerpsInitialLoadingState()
        let states = [
            presentation.update(isStale: true, hasData: true),
            presentation.update(isStale: true, hasData: true),
            presentation.update(isStale: false, hasData: true),
            presentation.update(isStale: true, hasData: true),
            presentation.update(isStale: false, hasData: true),
        ]
        #expect(states == [true, true, false, false, false])
    }

    @Test func newScreensAndResetDataRequireTheirOwnFreshPresentation() {
        var first = PerpsInitialLoadingState()
        var anotherScreenOrAccount = PerpsInitialLoadingState()
        let states = [
            first.update(isStale: false, hasData: true),
            anotherScreenOrAccount.update(isStale: true, hasData: true),
            first.update(isStale: true, hasData: true),
            first.update(isStale: true, hasData: false),
            first.update(isStale: true, hasData: true),
            first.update(isStale: false, hasData: true),
        ]
        #expect(states == [false, true, false, true, true, false])
    }
}
