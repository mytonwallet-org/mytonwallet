//
//  MAssetsAndActivityData.swift
//  WalletCore
//
//  Created by Sina on 7/5/24.
//

import WalletContext

public struct MAssetsAndActivityData: Equatable {
    
    static let defaultData = MAssetsAndActivityData(dictionary: nil)
    
    // These tokens will be visible even if they are no cost tokens! Because user checked them manually!
    public var alwaysShownSlugs: Set<String>
    
    // Hidden tokens won't be shown in Home-Page wallet tokens
    public var alwaysHiddenSlugs: Set<String>
    
    // Deleted tokens won't be shown at all
    public var deletedSlugs: Set<String>
    
    // AddedTokens show tokens will be shown even if user don't have them!
    public var importedSlugs: Set<String>
    
    init(dictionary: [String: Any]?) {
        if let dictionary {
            self.alwaysShownSlugs = Set(dictionary["alwaysShownSlugs"] as? [String] ?? [])
            self.alwaysHiddenSlugs = Set(dictionary["alwaysHiddenSlugs"] as? [String] ?? [])
            self.deletedSlugs = Set(dictionary["deletedSlugs"] as? [String] ?? [])
            self.importedSlugs = Set(dictionary["importedSlugs"] as? [String] ?? [])
        } else {
            self.alwaysShownSlugs = []
            self.alwaysHiddenSlugs = []
            self.deletedSlugs = []
            self.importedSlugs = []
        }
    }
    
    var toDictionary: [String: Any] {
        return [
            "alwaysHiddenSlugs": Array(alwaysHiddenSlugs),
            "alwaysShownSlugs": Array(alwaysShownSlugs),
            "deletedSlugs": Array(deletedSlugs),
            "importedSlugs": Array(importedSlugs)
        ]
    }
}
