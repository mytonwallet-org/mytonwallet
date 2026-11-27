import Foundation
import CryptoKit

public struct GiftTradeRecoveryState: Sendable {
    public let phase: Int
    public let query: String
    public let seller: String
    public let initiator: String
    public let codeHash: String
    public let stateHash: String
    public let observedAt: Int64
    public init(phase: Int, query: String, seller: String, initiator: String, codeHash: String, stateHash: String, observedAt: Int64) {
        self.phase = phase; self.query = query; self.seller = seller; self.initiator = initiator
        self.codeHash = codeHash; self.stateHash = stateHash; self.observedAt = observedAt
    }
}
public struct GiftTradeRecoveryDecision: Sendable, Equatable {
    public let action: String
    public let query: String?
}
@frozen public enum GiftTradeRecovery {
    /// No signing or timeout-based compensation. A trusted state reader must authenticate this input.
    public static func decide(_ state: GiftTradeRecoveryState, account: String, allowedCodeHashes: Set<String>, now: Int64) throws -> GiftTradeRecoveryDecision {
        guard [account, state.seller, state.initiator].allSatisfy({ GiftTradeReference.matches($0, pattern: "0:[a-f0-9]{64}") }),
              [state.codeHash, state.stateHash].allSatisfy({ GiftTradeReference.matches($0, pattern: "[a-f0-9]{64}") }),
              allowedCodeHashes.contains(state.codeHash), (0...11).contains(state.phase),
              (0...0xffffffff).contains(now), state.observedAt >= 0, state.observedAt <= now, now - state.observedAt <= 15,
              GiftTradeReference.matches(state.query, pattern: "0|[1-9][0-9]{0,19}"), let query = UInt64(state.query) else { throw GiftTradeError.staleReview }
        switch state.phase {
        case 4, 8: return GiftTradeRecoveryDecision(action: "reconcile", query: nil)
        case 3, 5, 6, 7: return GiftTradeRecoveryDecision(action: "drive", query: state.query)
        case 11:
            guard account == state.seller || account == state.initiator, query < UInt64.max else { throw GiftTradeError.staleReview }
            return GiftTradeRecoveryDecision(action: "retry-return", query: String(query + 1))
        default: return GiftTradeRecoveryDecision(action: "none", query: nil)
        }
    }
}

public struct GiftTradeReference: Equatable, Sendable {
    public let network: String
    public let kind: String
    public let nft: String
    public let contract: String

    public init(network: String, kind: String, nft: String, contract: String) throws {
        guard ["-239", "-3"].contains(network), ["sale", "offer"].contains(kind),
              Self.matches(nft, pattern: "0:[0-9a-f]{64}"),
              Self.matches(contract, pattern: "0:[0-9a-f]{64}") else { throw GiftTradeError.invalidReference }
        self.network = network
        self.kind = kind
        self.nft = nft
        self.contract = contract
    }

    public var encoded: String {
        "ton-gift-trade://v1/\(kind)?network=\(network)&nft=\(nft)&contract=\(contract)"
    }

    public static func decode(_ text: String, expectedNetwork: String) throws -> Self {
        guard text.utf8.count <= 256 else { throw GiftTradeError.invalidReference }
        let pattern = "ton-gift-trade://v1/(sale|offer)\\?network=(-239|-3)&nft=(0:[0-9a-f]{64})&contract=(0:[0-9a-f]{64})"
        let regex = try NSRegularExpression(pattern: pattern)
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: fullRange), match.range == fullRange else {
            throw GiftTradeError.invalidReference
        }
        func group(_ index: Int) throws -> String {
            guard let range = Range(match.range(at: index), in: text) else { throw GiftTradeError.invalidReference }
            return String(text[range])
        }
        let result = try Self(network: group(2), kind: group(1), nft: group(3), contract: group(4))
        guard result.network == expectedNetwork else { throw GiftTradeError.invalidReference }
        return result
    }

    static func matches(_ value: String, pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return regex.firstMatch(in: value, range: range)?.range == range
    }
}

@frozen public enum GiftTradeError: Error { case invalidReference, invalidAmount, staleReview }

public struct GiftTradeAmounts {
    public static func parseTon(_ text: String) throws -> String {
        guard GiftTradeReference.matches(text, pattern: "(0|[1-9][0-9]{0,27})(\\.[0-9]{1,9})?") else {
            throw GiftTradeError.invalidAmount
        }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        let fraction = parts.count == 2 ? String(parts[1]) : ""
        let digits = String(parts[0]) + fraction + String(repeating: "0", count: 9 - fraction.count)
        let nano = String(digits.drop(while: { $0 == "0" }))
        let maximum = "1329227995784915872903807060280344575"
        guard !nano.isEmpty, nano.count < maximum.count || (nano.count == maximum.count && nano <= maximum) else {
            throw GiftTradeError.invalidAmount
        }
        return nano
    }
}

@MainActor public final class GiftTradeReviewScope {
    public struct Token: Sendable, Equatable {
        fileprivate let id: UUID
        fileprivate let account: String
        fileprivate let network: String
        fileprivate let intent: GiftTradeBoundIntent?
    }
    private var account: String
    private var network: String
    private var current: Token?
    private var consumed: Token?

    public init(account: String, network: String) throws {
        _ = try GiftTradeReference(network: network, kind: "sale", nft: account, contract: account)
        self.account = account
        self.network = network
    }
    public func cancel() { current = nil; consumed = nil }
    public func switchAccount(account: String, network: String) throws {
        cancel()
        _ = try GiftTradeReference(network: network, kind: "sale", nft: account, contract: account)
        self.account = account
        self.network = network
    }
    public func begin() -> Token {
        cancel()
        let token = Token(id: UUID(), account: account, network: network, intent: nil)
        current = token
        return token
    }
    public func isCurrent(_ token: Token) -> Bool { current == token }
    public func begin(intent: GiftTradeBoundIntent, now: Int64) throws -> Token {
        cancel()
        guard intent.account == account, intent.network == network else { throw GiftTradeError.staleReview }
        try intent.checkTime(now)
        let token = Token(id: UUID(), account: account, network: network, intent: intent)
        current = token
        return token
    }
    public func consume(_ token: Token) throws {
        guard current == token else { throw GiftTradeError.staleReview }
        current = nil
        consumed = token
    }
    public func checkAfterAwait(_ token: Token) throws {
        guard consumed == token, account == token.account, network == token.network else {
            throw GiftTradeError.staleReview
        }
    }
    /// Trusted local validation only. No signer, transaction submission or RPC proof verifier is provided.
    public func complete(_ token: Token, intentId: String, stateHash: String, observedAt: Int64, now: Int64,
                         handoff: (GiftTradeBoundIntent) -> Void) throws {
        try checkAfterAwait(token)
        consumed = nil
        guard let intent = token.intent else { throw GiftTradeError.staleReview }
        try intent.checkTime(now)
        guard intent.id == intentId, intent.stateHash == stateHash,
              observedAt >= 0, observedAt <= now, now - observedAt <= 15 else { throw GiftTradeError.staleReview }
        handoff(intent)
    }
}

public struct GiftTradeMessage: Equatable, Sendable {
    public let to: String
    public let amount: String
    public let payload: String?
    public let stateInit: String?
    public init(to: String, amount: String, payload: String?, stateInit: String?) {
        self.to = to; self.amount = amount; self.payload = payload; self.stateInit = stateInit
    }
}

/// Immutable confirmation binding; cell syntax is checked, but structural BOC/chain validation is separate.
public struct GiftTradeBoundIntent: Equatable, Sendable {
    public let account: String
    public let network: String
    public let reference: GiftTradeReference
    public let action: String
    public let counterparty: String
    public let amount: String
    public let fee: String
    public let royalty: String
    public let gasBudget: String
    public let expiresAt: Int64
    public let feeRecipient: String
    public let royaltyRecipient: String
    public let stateHash: String
    public let authority: String
    public let provider: String
    public let messages: [GiftTradeMessage]
    public let id: String

    public init(account: String, network: String, reference: GiftTradeReference, action: String,
                counterparty: String, amount: String, fee: String, royalty: String, gasBudget: String,
                expiresAt: Int64, feeRecipient: String, royaltyRecipient: String, stateHash: String,
                authority: String, provider: String, messages: [GiftTradeMessage]) throws {
        _ = try GiftTradeReference(network: network, kind: "sale", nft: account, contract: account)
        let saleActions = ["list", "buy", "cancel-sale"]
        guard (saleActions + ["make-offer", "accept-offer", "cancel-offer"]).contains(action),
              reference.network == network, reference.kind == (saleActions.contains(action) ? "sale" : "offer"),
              [counterparty, feeRecipient, royaltyRecipient, authority].allSatisfy({ GiftTradeReference.matches($0, pattern: "0:[0-9a-f]{64}") }),
              expiresAt >= 0, expiresAt <= 0xffffffff,
              GiftTradeReference.matches(stateHash, pattern: "[a-f0-9]{64}"),
              GiftTradeReference.matches(provider, pattern: "[a-z][a-z0-9-]{0,31}"),
              (1...4).contains(messages.count) else { throw GiftTradeError.invalidReference }
        try Self.coins(amount, positive: !action.hasPrefix("cancel"))
        try Self.coins(fee); try Self.coins(royalty); try Self.coins(gasBudget)
        guard action.hasPrefix("cancel") || Self.less(Self.add(fee, royalty), amount) else { throw GiftTradeError.invalidAmount }
        var total = "0"
        for message in messages {
            guard GiftTradeReference.matches(message.to, pattern: "0:[0-9a-f]{64}") else { throw GiftTradeError.invalidReference }
            try Self.coins(message.amount, positive: true)
            total = Self.add(total, message.amount)
            for cell in [message.payload, message.stateInit].compactMap({ $0 }) {
                guard !cell.isEmpty, cell.utf8.count <= 65536, cell.utf8.count % 4 == 0,
                      GiftTradeReference.matches(cell, pattern: "[A-Za-z0-9+/]+={0,2}") else { throw GiftTradeError.invalidReference }
            }
        }
        try Self.coins(total, positive: true)
        let fields = ["wallet-gift-intent-v2", action, account, network, reference.encoded, counterparty, amount, fee,
                      royalty, gasBudget, String(expiresAt), feeRecipient, royaltyRecipient, stateHash, authority,
                      provider, account, network, String(expiresAt), String(messages.count)] +
            messages.flatMap { [$0.to, $0.amount, $0.payload ?? "-", $0.stateInit ?? "-"] }
        guard fields.allSatisfy({ $0.utf8.allSatisfy({ $0 >= 32 && $0 <= 126 }) }) else { throw GiftTradeError.invalidReference }
        let wire = fields.map { "\($0.utf8.count):\($0)" }.joined()
        self.id = SHA256.hash(data: Data(wire.utf8)).map { String(format: "%02x", $0) }.joined()
        self.account = account; self.network = network; self.reference = reference; self.action = action
        self.counterparty = counterparty; self.amount = amount; self.fee = fee; self.royalty = royalty; self.gasBudget = gasBudget
        self.expiresAt = expiresAt; self.feeRecipient = feeRecipient; self.royaltyRecipient = royaltyRecipient
        self.stateHash = stateHash; self.authority = authority; self.provider = provider; self.messages = messages
    }
    public func checkTime(_ now: Int64) throws {
        guard now >= 0, now <= 0xffffffff, expiresAt > now, expiresAt - now <= 300 else { throw GiftTradeError.staleReview }
    }
    fileprivate static func less(_ a: String, _ b: String) -> Bool { a.count < b.count || (a.count == b.count && a < b) }
    fileprivate static func coins(_ value: String, positive: Bool = false) throws {
        let maximum = "1329227995784915872903807060280344575"
        guard GiftTradeReference.matches(value, pattern: "0|[1-9][0-9]{0,36}"), !positive || value != "0",
              value == maximum || less(value, maximum) else { throw GiftTradeError.invalidAmount }
    }
    fileprivate static func add(_ a: String, _ b: String) -> String {
        let x = Array(a.utf8.reversed()), y = Array(b.utf8.reversed())
        var output: [UInt8] = [], carry = 0
        for index in 0..<max(x.count, y.count) {
            let sum = (index < x.count ? Int(x[index]) - 48 : 0) + (index < y.count ? Int(y[index]) - 48 : 0) + carry
            output.append(UInt8(sum % 10 + 48)); carry = sum / 10
        }
        if carry > 0 { output.append(UInt8(carry + 48)) }
        return String(decoding: output.reversed(), as: UTF8.self)
    }
}

/// Buyer display/eligibility checks only. Signing, current funds and production state are separate integrations.
public struct GiftTradePurchaseCost: Equatable, Sendable {
    public let price: String
    public let includedFee: String
    public let includedRoyalty: String
    public let gasBudget: String
    public let walletFeeReserve: String
    public let maximumDebit: String
    public static func review(_ intent: GiftTradeBoundIntent, accountKind: String, spendableBalance: String,
                              walletFeeReserve: String, maxGasBudget: String, maxWalletFeeReserve: String, now: Int64) throws -> Self {
        try intent.checkTime(now)
        guard intent.action == "buy", ["software", "hardware"].contains(accountKind) else { throw GiftTradeError.staleReview }
        for value in [spendableBalance, walletFeeReserve, maxGasBudget, maxWalletFeeReserve] { try GiftTradeBoundIntent.coins(value) }
        let sent = intent.messages.reduce("0") { GiftTradeBoundIntent.add($0, $1.amount) }
        let total = GiftTradeBoundIntent.add(sent, walletFeeReserve)
        try GiftTradeBoundIntent.coins(total, positive: true)
        guard !GiftTradeBoundIntent.less(sent, intent.amount),
              total == GiftTradeBoundIntent.add(intent.amount, intent.gasBudget),
              !GiftTradeBoundIntent.less(maxGasBudget, intent.gasBudget),
              !GiftTradeBoundIntent.less(maxWalletFeeReserve, walletFeeReserve),
              !GiftTradeBoundIntent.less(spendableBalance, total) else { throw GiftTradeError.invalidAmount }
        return Self(price: intent.amount, includedFee: intent.fee, includedRoyalty: intent.royalty,
                    gasBudget: intent.gasBudget, walletFeeReserve: walletFeeReserve, maximumDebit: total)
    }
}
