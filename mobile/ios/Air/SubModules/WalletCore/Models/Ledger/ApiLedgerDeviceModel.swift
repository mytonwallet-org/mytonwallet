
public struct ApiLedgerDeviceModel: Codable, Sendable {
    public var id: String
    public var productName: String
    
    public init(id: String, productName: String) {
        self.id = id
        self.productName = productName
    }
}
