//
//  ApiDappRequest.swift
//  MyTonWalletAir
//
//  Created by nikstar on 27.08.2025.
//

public struct ApiDappRequest: Hashable, Codable {
    var url: String?
    var isUrlEnsured: Bool?
    var accountId: String?
    var identifier: String?
    var sseOptions: ApiSseOptions?
    
    public init(url: String?, isUrlEnsured: Bool?, accountId: String?, identifier: String?, sseOptions: ApiSseOptions?) {
        self.url = url
        self.isUrlEnsured = isUrlEnsured
        self.accountId = accountId
        self.identifier = identifier
        self.sseOptions = sseOptions
    }
}
