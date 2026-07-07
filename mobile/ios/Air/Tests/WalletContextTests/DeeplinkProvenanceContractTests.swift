import Testing
import WalletContext

@Suite("Deeplink Provenance Contract")
struct DeeplinkProvenanceContractTests {
    @Test
    func `trusted sources can route Offramp`() {
        #expect(DeeplinkOpenSource.generic.canRouteOfframp)
        #expect(DeeplinkOpenSource.exploreSearchBar.canRouteOfframp)
    }

    @Test
    func `untrusted sources cannot route Offramp`() {
        #expect(!DeeplinkOpenSource.inAppBrowser.canRouteOfframp)
        #expect(!DeeplinkOpenSource.qrScan.canRouteOfframp)
    }
}
