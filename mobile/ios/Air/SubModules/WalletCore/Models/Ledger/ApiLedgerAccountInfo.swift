
import WalletContext

public struct ApiLedgerAccountInfo: Codable {
  public var byChain: [String: ApiAnyChainWallet]
  public var driver: ApiLedgerDriver
  public var deviceId: String?
  public var deviceName: String?
    
    public init(byChain: [String : ApiAnyChainWallet], driver: ApiLedgerDriver, deviceId: String? = nil, deviceName: String? = nil) {
        self.byChain = byChain
        self.driver = driver
        self.deviceId = deviceId
        self.deviceName = deviceName
    }
}
