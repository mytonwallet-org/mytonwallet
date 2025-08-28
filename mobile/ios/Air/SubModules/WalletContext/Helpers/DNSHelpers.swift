//
//  DNSHelpers.swift
//  MyTonWalletAir
//
//  Created by Sina on 10/17/24.
//

import Foundation


private struct ZonesRegex {
    static let ton = try! NSRegularExpression(pattern: "^([\\-\\da-z]+\\.){0,2}([\\-\\da-z]{4,126})\\.ton$", options: .caseInsensitive)
    static let t_me = try! NSRegularExpression(pattern: "^([\\-\\da-z]+\\.){0,2}([\\-_\\da-z]{4,126})\\.t\\.me$", options: .caseInsensitive)
    static let vip = try! NSRegularExpression(pattern: #"^(?<base>([\-\da-z]+\.){0,2}([\da-z]{1,24}))\.(ton\.vip|vip\.ton|vip)$"#, options: .caseInsensitive)
    static let gram = try! NSRegularExpression(pattern: #"^(?<base>([\-\da-z]+\.){0,2}([\da-z]{1,24}))\.(gram)$"#, options: .caseInsensitive)
}
private let regexes = [
    ZonesRegex.ton,
    ZonesRegex.t_me,
    ZonesRegex.vip,
    ZonesRegex.gram
]

public class DNSHelpers {
    private init() {}

    public static func isDnsDomain(_ value: String) -> Bool {
        return regexes.contains { regex in
            let range = NSRange(location: 0, length: value.utf16.count)
            return regex.firstMatch(in: value, options: [], range: range) != nil
        }
    }
}
