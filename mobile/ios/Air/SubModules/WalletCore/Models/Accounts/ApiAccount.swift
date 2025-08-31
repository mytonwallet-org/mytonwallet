
import UIKit
import WalletContext

public struct ApiBip39Account {
  public var type = "bip39"
  public var mnemonicEncrypted: String
  public var tron: ApiTronWallet
  public var ton: ApiTonWallet
}

public struct ApiTonAccount {
  public var type = "ton"
  public var mnemonicEncrypted: String
  public var ton: ApiTonWallet
}

public struct ApiLedgerAccount: Equatable, Hashable, Codable {
  public var type = "ledger"
  public var ton: ApiTonWallet
  public var driver: ApiLedgerDriver
  public var deviceId: String?
  public var deviceName: String?
}
