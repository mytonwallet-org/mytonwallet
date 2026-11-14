import Foundation
import Testing
import WalletCore
import WalletContext
@testable import UITransaction

@Suite
struct ActivityDetailsFeeTests {
    private let usdc = PerpsFormatting.usdc
    private let eth = ApiChain.arbitrum.nativeToken

    @Test
    func `gasless transfer fee is in the transferred token`() throws {
        let activity = try decodeTransfer(extra: #","extra":{"isGasless":true}"#)

        let fee = ActivityDetailsView.computeDisplayFee(of: activity, token: usdc, nativeToken: eth)

        #expect(fee == MFee(precision: .exact, terms: .init(token: 31_000, native: nil, stars: nil), nativeSum: nil))
    }

    @Test
    func `transfer fee without the gasless mark is native`() throws {
        let activity = try decodeTransfer(extra: "")

        let fee = ActivityDetailsView.computeDisplayFee(of: activity, token: usdc, nativeToken: eth)

        #expect(fee == MFee(precision: .exact, terms: .init(token: nil, native: 31_000, stars: nil), nativeSum: nil))
    }

    @Test
    func `gasless swap fee is in the sold token`() throws {
        let activity = try decodeSwap(extra: #","extra":{"isGasless":true}"#)

        let fee = ActivityDetailsView.computeDisplayFee(of: activity, token: usdc, nativeToken: eth)

        #expect(fee == MFee(precision: .exact, terms: .init(token: 500_000, native: nil, stars: nil), nativeSum: nil))
    }

    @Test
    func `swap fee without the gasless mark is native`() throws {
        let activity = try decodeSwap(extra: "")

        let fee = ActivityDetailsView.computeDisplayFee(of: activity, token: usdc, nativeToken: eth)

        #expect(fee == MFee(precision: .exact, terms: .init(token: nil, native: 500_000_000_000_000_000, stars: nil), nativeSum: nil))
    }

    private func decodeTransfer(extra: String) throws -> ApiActivity {
        try JSONDecoder().decode(ApiActivity.self, from: Data("""
            {"kind":"transaction","id":"gasless-transfer","timestamp":1000,"amount":"-5000000",
            "fromAddress":"from","toAddress":"to","fee":"31000","slug":"\(usdc.slug)","isIncoming":false,
            "status":"completed"\(extra)}
            """.utf8))
    }

    private func decodeSwap(extra: String) throws -> ApiActivity {
        try JSONDecoder().decode(ApiActivity.self, from: Data("""
            {"kind":"swap","id":"gasless-swap","timestamp":1000,"from":"\(usdc.slug)","fromAmount":"5",
            "to":"\(eth.slug)","toAmount":"0.001","networkFee":"0.5","status":"completed","transactionIds":{}\(extra)}
            """.utf8))
    }
}
