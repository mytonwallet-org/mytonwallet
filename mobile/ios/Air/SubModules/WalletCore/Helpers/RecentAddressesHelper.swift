//
//  RecentAddressesHelper.swift
//  WalletCore
//
//  Created by Sina on 4/19/24.
//

import Foundation
import WalletContext

public class RecentAddressesHelper {
    private init() {}
    
    public static func recentAddresses(accountId: String) -> [MRecentAddress] {
        guard let recentAddressesData =
                KeychainHelper.recentAddresses(accountId: accountId)?.data(using: .utf8) else {
            return []
        }
        let recentAddresses = try? JSONDecoder().decode([MRecentAddress].self, from: recentAddressesData)
        return recentAddresses ?? []
    }
    
    public static func saveRecentAddress(accountId: String, recentAddress: MRecentAddress) {
        var arrRecents = recentAddresses(accountId: accountId)
        arrRecents.removeAll { it in
            it.address == recentAddress.address &&
            it.addressAlias == recentAddress.addressAlias
        }
        arrRecents.insert(recentAddress, at: 0)
        let arrRecentsData = try? JSONEncoder().encode(arrRecents)
        if let arrRecentsData {
            KeychainHelper.save(accountId: accountId,
                                recentAddresses: String(data: arrRecentsData, encoding: .utf8)!)
        }
    }
    
    static func clearRecentAddresses(accountId: String) {
        KeychainHelper.save(accountId: accountId, recentAddresses: nil)
    }
}
