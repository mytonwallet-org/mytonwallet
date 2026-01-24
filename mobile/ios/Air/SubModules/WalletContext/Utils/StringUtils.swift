//
//  StringUtils.swift
//  WalletContext
//
//  Created by Sina on 5/13/23.
//

import Foundation
import UIKit

public extension String {

    subscript (i: Int) -> String {
        return self[i ..< i + 1]
    }

    func substring(fromIndex: Int) -> String {
        return self[min(fromIndex, count) ..< count]
    }

    func substring(toIndex: Int) -> String {
        return self[0 ..< max(0, toIndex)]
    }

    subscript (r: Range<Int>) -> String {
        let range = Range(uncheckedBounds: (lower: max(0, min(count, r.lowerBound)),
                                            upper: min(count, max(0, r.upperBound))))
        let start = index(startIndex, offsetBy: range.lowerBound)
        let end = index(start, offsetBy: range.upperBound - range.lowerBound)
        return String(self[start ..< end])
    }

    func normalizeArabicPersianNumeralStringToWestern() -> String {
        var string = self

        let numerals = [
            ("0", "٠", "۰"),
            ("1", "١", "۱"),
            ("2", "٢", "۲"),
            ("3", "٣", "۳"),
            ("4", "٤", "۴"),
            ("5", "٥", "۵"),
            ("6", "٦", "۶"),
            ("7", "٧", "۷"),
            ("8", "٨", "۸"),
            ("9", "٩", "۹"),
            (",", "٫", "٫")
        ]

        for (western, arabic, persian) in numerals {
            string = string.replacingOccurrences(of: arabic, with: western)
            string = string.replacingOccurrences(of: persian, with: western)
        }

        return string
    }

    var toDictionary: [String: Any]? {
        if let data = data(using: .utf8) {
            do {
                let json = try JSONSerialization.jsonObject(with: data, options: .mutableContainers) as? [String: Any]
                return json
            } catch {
            }
        }
        return nil
    }

    var toArrayDictionary: [Any]? {
        if let data = data(using: .utf8) {
            do {
                let json = try JSONSerialization.jsonObject(with: data, options: .mutableContainers) as? [Any]
                return json
            } catch {
            }
        }
        return nil
    }

    /// Converts a base64-url encoded string to a base64 encoded string.
    ///
    /// https://tools.ietf.org/html/rfc4648#page-7
    func base64URLUnescaped() -> String {
        let replaced = replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        /// https://stackoverflow.com/questions/43499651/decode-base64url-to-base64-swift
        let padding = replaced.count % 4
        if padding > 0 {
            return replaced + String(repeating: "=", count: 4 - padding)
        } else {
            return replaced
        }
    }

    /// Converts a base64 encoded string to a base64-url encoded string.
    ///
    /// https://tools.ietf.org/html/rfc4648#page-7
    func base64URLEscaped() -> String {
        return replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    var gradientColors: [CGColor] {
        var combinedValue: Int = 0
        for scalar in unicodeScalars {
            combinedValue += Int(scalar.value)
        }
        return WColors.gradients[Int(combinedValue) % WColors.gradients.count]
    }

    var shortChars: String {
        var shortText = ""
        let splitted = components(separatedBy: " ")
        for i in 0 ..< min(2, splitted.count) {
            if let char = splitted[i].first {
                shortText += "\(char)"
            }
        }
        return shortText
    }

    var base64ToHex: String {
        if let data = Data(base64Encoded: self) {
            return data.map { String(format: "%02x", $0) }.joined()
        }
        return self
    }

    var leadingZeros: Int {
        var count = 0
        for character in self {
            if character == "0" {
                count += 1
            } else {
                break
            }
        }
        return count
    }
    
    var reverse: String {
        String(self.reversed())
    }
}
