import SwiftUI
import Testing
import WalletCore
import WalletResources
@testable import UIToken

@MainActor
@Suite("Token Header Balance Layout")
struct TokenHeaderBalanceLayoutTests {
    @Test
    func `collapsed equivalent renders identically with and without a long daily change`() throws {
        _ = WalletResourcesBundle.bundle.load()
        func render(progress: CGFloat, hasChange: Bool) throws -> Data {
            let renderer = ImageRenderer(content: TokenHeaderEquivalentView(
                amount: .fromDouble(123_456_789.12, .USD),
                change: hasChange ? .fromDouble(12_345_678.90, .USD) : nil,
                percent: hasChange ? 0.123456 : nil,
                expansionProgress: progress
            )
            .minimumScaleFactor(0.1)
            .frame(width: 300, height: 30)
            .environment(\.colorScheme, .light))
            renderer.scale = 2
            return try #require(renderer.uiImage?.pngData())
        }
        let collapsed = try render(progress: 0, hasChange: true)
        #expect(collapsed == (try render(progress: 0, hasChange: false)))
        let expanded = try render(progress: 1, hasChange: true)
        #expect(expanded != (try render(progress: 1, hasChange: false)))
        Attachment.record(collapsed, named: "token-collapsed-balance.png")
        Attachment.record(expanded, named: "token-expanded-balance.png")
    }
}
