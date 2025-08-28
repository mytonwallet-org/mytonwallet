//
//  MTransactionDraft.swift
//  WalletCore
//
//  Created by Sina on 5/10/24.
//

import Foundation
import BigIntLib
import WalletContext

/// aka **ApiCheckTransactionDraftResult**
public struct MTransactionDraft: Equatable, Codable, Sendable {
    /// The full fee that will be appended to the transaction. Measured in the native token. It's charged on top of the
    /// transferred amount, unless it's a full-TON transfer.
    public let fee: BigInt?
    
    /// An approximate fee that will be actually spent. The difference between `fee` and this number is called "excess" and
    /// will be returned back to the wallet. Measured in the native token. Undefined means that it can't be estimated.
    /// If the value is equal to `fee`, then it's known that there will be no excess.
    public let realFee: BigInt?
    public let addressName: String?
    public let isScam: Bool?
    public let resolvedAddress: String?
    public let isToAddressNew: Bool?
    public let isBounceable: Bool?
    public let isMemoRequired: Bool?
    public let error: ApiAnyDisplayError?

    /// Describes a possibility to use diesel for this transfer. The UI should prefer diesel when this field is defined,
    /// and the diesel status is not "not-available". When the diesel is available, and the UI decides to use it, the `fee`
    /// and `realFee` fields should be ignored, because they don't consider an extra transfer of the diesel to the
    /// MTW wallet.
    public let diesel: MDiesel?
    
    // staking extension
    public var tokenAmount: BigInt?
    public var type: String?
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.fee = try container.decodeIfPresent(BigInt.self, forKey: .fee)
        self.realFee = try container.decodeIfPresent(BigInt.self, forKey: .realFee)
        self.addressName = try container.decodeIfPresent(String.self, forKey: .addressName)
        self.isScam = try container.decodeIfPresent(Bool.self, forKey: .isScam)
        self.resolvedAddress = try container.decodeIfPresent(String.self, forKey: .resolvedAddress)
        self.isToAddressNew = try container.decodeIfPresent(Bool.self, forKey: .isToAddressNew)
        self.isBounceable = try container.decodeIfPresent(Bool.self, forKey: .isBounceable)
        self.isMemoRequired = try container.decodeIfPresent(Bool.self, forKey: .isMemoRequired)
        do {
            self.error = try container.decodeIfPresent(ApiAnyDisplayError.self, forKey: .error)
        } catch {
            Log.shared.error("unexpected error: \((try? container.decodeIfPresent(ApiAnyDisplayError.self, forKey: .error)) as Any, .public)")
            self.error = .unexpected
        }
        self.diesel = try container.decodeIfPresent(MDiesel.self, forKey: .diesel)
        self.tokenAmount = try? container.decodeIfPresent(BigInt.self, forKey: .tokenAmount)
        self.type = container.decodeOptional(String.self, forKey: .type)
    }
}


extension MTransactionDraft {
    
    /// Like **diesel** but checks that status is not "not-abailable"
    public var dieselAvailable: MDiesel? {
        if let diesel, diesel.status != .notAvailable {
            return diesel
        }
        return nil
    }
}

// TODO: surface other errors where appropriate
public func handleDraftError(_ draft: MTransactionDraft) throws {
    if let error = draft.error, error == .serverError {
        throw BridgeCallError.message(.serverError, draft)
    }
}
