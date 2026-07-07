import Foundation
import SwiftUI
import UIKit

#if GRAM_WALLET
let SELF_PROTOCOL = "gramwallet://"
#else
let SELF_PROTOCOL = "mtw://"
#endif

let TONCOIN_SLUG = "toncoin"
let TON_USDT_SLUG = "ton-eqcxe6mutq"
let TRX_SLUG = "trx"
let TRON_USDT_SLUG = "tron-tr7nhqjekq"
let SOLANA_SLUG = "sol"
let SOLANA_USDT_MAINNET_SLUG = "solana-es9vmfrzac"
let MYCOIN_SLUG = "ton-eqcfvnlrbn"
let STAKED_TON_SLUG = "ton-eqcqc6ehrj"
let STAKED_MYCOIN_SLUG = "ton-eqcbzvsfwq"
let TON_USDE_SLUG = "ton-eqaib6kmdf"
let TON_TSUSDE_SLUG = "ton-eqdq5uuyph"

let widgetLocalizationBundle = Bundle.main

typealias ApiHistoryList = [[Double]]

func localized(_ keyAndDefault: String) -> LocalizedStringResource {
    LocalizedStringResource(String.LocalizationValue(keyAndDefault), bundle: widgetLocalizationBundle)
}

func lang(_ keyAndDefault: String) -> String {
    NSLocalizedString(keyAndDefault, bundle: widgetLocalizationBundle, comment: "")
}

public enum CompactRoundedWeight {
    case bold
}

public extension UIFont {
    class func compactRounded(ofSize size: CGFloat, weight: CompactRoundedWeight) -> UIFont {
        switch weight {
        case .bold:
            UIFont(name: "SFCompactRounded-Bold", size: size)!
        }
    }
}

public extension Font {
    static func compactRounded(size: CGFloat, weight: CompactRoundedWeight) -> Font {
        Font(UIFont.compactRounded(ofSize: size, weight: weight))
    }
}

func formatPercent(_ value: Double, decimals: Int = 2, showPlus: Bool = true, showMinus: Bool = true) -> String {
    let value = (value * 100).rounded(decimals: decimals)
    let number = abs(value)

    if showPlus && value > 0 {
        return "+\(number)%"
    }
    if showMinus && value < 0 {
        return "-\(number)%"
    }
    return "\(number)%"
}

extension Double {
    func rounded(decimals: Int) -> Double {
        let multiplier = pow(10.0, Double(decimals))
        return (self * multiplier).rounded() / multiplier
    }
}

extension UIColor {
    convenience init(hex hexString: String) {
        let hex = hexString
            .trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            .uppercased()
        var intValue: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&intValue)

        let red: UInt64
        let green: UInt64
        let blue: UInt64
        let alpha: UInt64

        switch hex.count {
        case 3:
            alpha = 255
            red = (intValue >> 8) * 17
            green = (intValue >> 4 & 0xF) * 17
            blue = (intValue & 0xF) * 17
        case 6:
            alpha = 255
            red = intValue >> 16
            green = intValue >> 8 & 0xFF
            blue = intValue & 0xFF
        case 8:
            alpha = intValue >> 24
            red = intValue >> 16 & 0xFF
            green = intValue >> 8 & 0xFF
            blue = intValue & 0xFF
        default:
            alpha = 255
            red = 0
            green = 0
            blue = 0
        }

        self.init(
            red: CGFloat(red) / 255,
            green: CGFloat(green) / 255,
            blue: CGFloat(blue) / 255,
            alpha: CGFloat(alpha) / 255
        )
    }
}
