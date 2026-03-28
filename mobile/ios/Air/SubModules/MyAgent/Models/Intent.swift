import Foundation

/// All supported intent types.
public enum IntentType: String, Codable, Sendable {
    case question
    case searchNews
    case sendToken
    case receive
    case swap
    case buyWithCard
    case buyWithCrypto
    case price
    case stake
    case portfolio
}

/// A classified intent with extracted parameters.
public struct Intent: Codable, Sendable {
    public let type: IntentType

    // searchNews
    public let query: String?

    // sendToken
    public let to: String?

    // receive
    public let address: String?
    public let comment: String?

    // sendToken / receive / buyWithCard / price
    public let amount: Double?
    public let token: String?

    // swap
    public let `in`: String?
    public let out: String?
    public let amountIn: Double?
    public let amountOut: Double?

    public init(
        type: IntentType,
        query: String? = nil,
        to: String? = nil,
        address: String? = nil,
        comment: String? = nil,
        amount: Double? = nil,
        token: String? = nil,
        in inToken: String? = nil,
        out outToken: String? = nil,
        amountIn: Double? = nil,
        amountOut: Double? = nil
    ) {
        self.type = type
        self.query = query
        self.to = to
        self.address = address
        self.comment = comment
        self.amount = amount
        self.token = token
        self.in = inToken
        self.out = outToken
        self.amountIn = amountIn
        self.amountOut = amountOut
    }

    /// Return a copy with the `to` field replaced.
    public func replacing(to newTo: String?) -> Intent {
        Intent(
            type: type,
            query: query,
            to: newTo,
            address: address,
            comment: comment,
            amount: amount,
            token: token,
            in: self.in,
            out: out,
            amountIn: amountIn,
            amountOut: amountOut
        )
    }

    /// Return a copy with the `address` field replaced.
    public func replacing(address newAddress: String?) -> Intent {
        Intent(
            type: type,
            query: query,
            to: to,
            address: newAddress,
            comment: comment,
            amount: amount,
            token: token,
            in: self.in,
            out: out,
            amountIn: amountIn,
            amountOut: amountOut
        )
    }
}

/// The full classifier output: detected language + list of intents.
public struct ClassificationResult: Sendable {
    public let intents: [Intent]
    public let detectedLang: String

    public init(intents: [Intent], detectedLang: String) {
        self.intents = intents
        self.detectedLang = detectedLang
    }
}
