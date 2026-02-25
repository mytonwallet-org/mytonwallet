//
//  WalletUtils.swift
//  WalletContext
//
//  Created by Sina on 3/20/24.
//

import Foundation
import UIKit

public let TON_CHAIN = "ton"
public let TRON_CHAIN = "tron"
public let SOLANA_CHAIN = "solana"

public let TONCOIN_SLUG = "toncoin"
public let TON_USDT_SLUG = "ton-eqcxe6mutq"
public let TRX_SLUG = "trx"
public let TRON_USDT_SLUG = "tron-tr7nhqjekq"
public let TRON_USDT_TESTNET_SLUG = "tron-tg3xxyexbk"
public let SOLANA_SLUG = "sol"
public let SOLANA_USDT_MAINNET_SLUG = "solana-es9vmfrzac"
public let MYCOIN_SLUG = "ton-eqcfvnlrbn"
public let STAKED_TON_SLUG = "ton-eqcqc6ehrj"
public let STAKED_MYCOIN_SLUG = "ton-eqcbzvsfwq"
public let TON_USDE_SLUG = "ton-eqaib6kmdf"
public let TON_TSUSDE_SLUG = "ton-eqdq5uuyph"

public let EARN_AVAILABLE_SLUGS = [TONCOIN_SLUG, MYCOIN_SLUG]

public let DIESEL_TOKENS = [
    "EQAvlWFDxGF2lXm67y4yzC17wYKD9A0guwPkMs1gOsM__NOT", // NOT
    "EQCxE6mUtQJKFnGfaROTKOt1lZbDiiX1kCixRv7Nw2Id_sDs", // USDT
    "EQCvxJy4eG8hyHBFsZ7eePxrRsUQSFE_jpptRAYBmcG_DOGS", // DOGS
    "EQD-cvR0Nz6XAyRBvbhz-abTrRC6sI5tvHvvpeQraV9UAAD7", // CATI
    "EQAJ8uWd7EBqsmpSWaRdf_I-8R8-XHwh3gsNKhy-UrdrPcUo", // HAMSTER
]

fileprivate let decimalSeparator = "."
public let signSpace = "\u{2009}"
fileprivate let thousandSpace: Character = " "

public let walletAddressLength: Int = 48
public let walletTextLimit: Int = 120

public var supportedTonConnectVersion = 2

public let appName = "MyTonWallet"
public var devicePlatform: String {
    switch UIDevice.current.userInterfaceIdiom {
    case .phone:
        return "iphone"
    case .pad:
        return "ipad"
    default:
        return ""
    }
}
public let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""

public func formatStartEndAddress(_ address: String, prefix: Int = 6, suffix: Int = 6, separator: String = "···") -> String {
    if address.count < prefix + suffix + 3 {
        return address
    }
    return "\(address.prefix(prefix))\(separator)\(address.suffix(suffix))"
}

public func formatAddressAttributed(
    _ address: String,
    startEnd: Bool,
    primaryFont: UIFont? = nil,
    secondaryFont: UIFont? = nil,
    primaryColor: UIColor? = nil,
    secondaryColor: UIColor? = nil,
    kerning: CGFloat? = nil
) -> NSAttributedString {
    let prefix = 6
    let suffix = 6

    let string = startEnd ? formatStartEndAddress(address, prefix: prefix, suffix: suffix) : address
    let len = (string as NSString).length
    let at = NSMutableAttributedString(string: string)
    if startEnd, len > prefix + suffix + 1 {

        let primaryFont = primaryFont ?? UIFont.systemFont(ofSize: 17, weight: .regular)
        let secondaryFont = secondaryFont ?? UIFont.systemFont(ofSize: 17, weight: .regular)
        let primaryColor = primaryColor ?? WTheme.primaryLabel
        let secondaryColor = secondaryColor ?? primaryColor

        at.addAttributes([
            .font: primaryFont,
            .foregroundColor: primaryColor,
        ], range: NSRange(location: 0, length: prefix))
        at.addAttributes([
            .font: secondaryFont,
            .foregroundColor: secondaryColor,
        ], range: NSRange(location: prefix, length: len - suffix - prefix))
        at.addAttributes([
            .font: primaryFont,
            .foregroundColor: primaryColor,
        ], range: NSRange(location: len - suffix, length: suffix))

    } else {

        let primaryFont = primaryFont ?? UIFont.systemFont(ofSize: 17, weight: .regular)
        let secondaryFont = secondaryFont ?? primaryFont
        let primaryColor = primaryColor ?? WTheme.primaryLabel
        let secondaryColor = secondaryColor ?? WTheme.secondaryLabel

        if len > 25 {
            at.addAttributes([
                .font: primaryFont,
                .foregroundColor: primaryColor,
            ], range: NSRange(location: 0, length: prefix))
            at.addAttributes([
                .font: secondaryFont,
                .foregroundColor: secondaryColor,
            ], range: NSRange(location: prefix, length: len-prefix-suffix))
            at.addAttributes([
                .font: primaryFont,
                .foregroundColor: primaryColor,
            ], range: NSRange(location: len-suffix, length: suffix))
            
            // insert zero-width spaces to fix line breaking
            let zws = NSAttributedString(string: "\u{200B}")
            for idx in (1..<len).reversed() {
                at.insert(zws, at: idx)
            }
        } else {
            at.addAttributes([
                .font: primaryFont,
                .foregroundColor: primaryColor,
            ], range: NSRange(location: 0, length: len))
        }
    }

    if let kerning {
        at.addAttributes([
            .kern: kerning
        ], range: NSRange(location: 0, length: len))
    }

    return at
}

fileprivate func insertGroupingSeparator(in string: String, separator: Character = thousandSpace, every nthPosition: Int = 3) -> String {
    var result = ""
    var count = 0
    var hasDot = string.contains(".")

    for char in string.reversed() {
        if hasDot {
            result.insert(char, at: result.startIndex)
            if char == "." {
                hasDot = false
            }
            continue
        }
        if count != 0 && count % nthPosition == 0 {
            result.insert(separator, at: result.startIndex)
        }
        result.insert(char, at: result.startIndex)
        count += 1
    }

    return result
}

public func integerPart(_ value: BigInt, tokenDecimals: Int) -> BigInt {
    var balanceText = "\(abs(value))"
    while balanceText.count < tokenDecimals + 1 {
        balanceText.insert("0", at: balanceText.startIndex)
    }
    balanceText.insert(contentsOf: decimalSeparator, at: balanceText.index(balanceText.endIndex, offsetBy: -tokenDecimals))
    let parts = balanceText.components(separatedBy: decimalSeparator)
    let integerPart = parts[0]
    return BigInt(integerPart) ?? 0
}

// format amount into string with separator
public func formatBigIntText(_ value: BigInt,
                            currency: String? = nil,
                            negativeSign: Bool = false,
                            positiveSign: Bool = false,
                            tokenDecimals: Int,
                            decimalsCount: Int? = nil,
                            forceCurrencyToRight: Bool = false,
                            roundUp: Bool = true) -> String {
    let rounded: BigInt = if let decimalsCount {
        value.rounded(digitsToRound: tokenDecimals - decimalsCount, roundHalfUp: roundUp)
    } else {
        value
    }
    var result = "\(abs(rounded))"
    while result.count < tokenDecimals + 1 {
        result.insert("0", at: result.startIndex)
    }
    result.insert(contentsOf: decimalSeparator, at: result.index(result.endIndex, offsetBy: -tokenDecimals))
    while result.hasSuffix("0") {
        result.removeLast()
    }
    if result.hasSuffix(decimalSeparator) {
        result.removeLast()
    }
    result = insertGroupingSeparator(in: result)

    if let currency, currency.count > 0 {
        if currency.count > 1 || forceCurrencyToRight || currency == "₽" {
            result = "\(result) \(currency)"
        } else {
            result = "\(currency)\(result)"
        }
    }

    if value < 0, negativeSign {
        result.insert(contentsOf: "-\(signSpace)", at: result.startIndex)
    } else if value >= 0, positiveSign {
        result.insert(contentsOf: "+\(signSpace)", at: result.startIndex)
    }

    return result
}

/// Expects value 0...1 (0.42 -> 42%)
public func formatPercent(_ value: Double, decimals: Int = 2, showPlus: Bool = true, showMinus: Bool = true) -> String {
    let value = (value * 100).rounded(decimals: decimals)
    return if showPlus && value > 0 {
        "+\(signSpace)\(value)%"
    } else if showMinus && value < 0 {
        "-\(signSpace)\(abs(value))%"
    } else {
        "\(abs(value))%"
    }
}

// timestamp into string
public func stringForTimestamp(timestamp: Int32, local: Bool = true) -> String {
    var t = Int(timestamp)
    var timeinfo = tm()
    if local {
        localtime_r(&t, &timeinfo)
    } else {
        gmtime_r(&t, &timeinfo)
    }

    return stringForShortTimestamp(hours: timeinfo.tm_hour, minutes: timeinfo.tm_min)
}

public func stringForShortTimestamp(hours: Int32, minutes: Int32) -> String {
    let hourString: String = hours < 10 ? "0\(hours)" : "\(hours)"
    if minutes >= 10 {
        return "\(hourString):\(minutes)"// \(periodString)"
    } else {
        return "\(hourString):0\(minutes)"// \(periodString)"
    }
}

public func amountValue(_ string: String, digits: Int) -> BigInt {
    let string = string
        .replacingOccurrences(of: ",", with: ".")
        .replacingOccurrences(of: " ", with: "")
    if let range = string.range(of: ".") {
        let integralPart = String(string[..<range.lowerBound])
        let fractionalPart = String(string[range.upperBound...])
        let string = integralPart + "\(fractionalPart.prefix(digits))" + String(repeating: "0", count: max(0, digits - fractionalPart.count))
        return BigInt(string) ?? 0
    } else if let integral = BigInt(string) {
        return integral * powI64(10, digits)
    }
    return 0
}

public func roundDecimals(_ amount: BigInt, decimals: Int, roundTo maxDecimals: Int) -> BigInt {
    let m = powI64(10, max(decimals - maxDecimals, 1))
    return amount - (amount % m)
}

// MARK: - Wallet URL Processor

public struct TonTransferUrl {
    public var address: String
    public var amount: BigInt?
    public var comment: String?
    public var token: String?
    public var bin: String?
    public var jetton: String?
    public var stateInit: String?
}

private let invalidWalletAddressCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_=").inverted
private func isValidWalletAddress(_ address: String) -> Bool {
    if address.count != 48 || address.rangeOfCharacter(from: invalidWalletAddressCharacters) != nil {
        return false
    }
    return true
}

public func parseTonTransferUrl(_ url: URL) -> TonTransferUrl? {
    guard (url.scheme == "ton" || url.scheme == "mtw") && url.host == "transfer" else {
        return nil
    }
    let updatedUrl = URL(string: url.absoluteString.replacingOccurrences(of: "+", with: "%20"), relativeTo: nil) ?? url

    let address = updatedUrl.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    guard isValidWalletAddress(address) else {
        return nil
    }
    
    var amount: BigInt?
    var comment: String?
    var token: String?
    var bin: String?
    var jetton: String?
    var stateInit: String?
    
    if let query = updatedUrl.query, let components = URLComponents(string: "/?" + query), let queryItems = components.queryItems {
        for queryItem in queryItems {
            if let value = queryItem.value {
                if queryItem.name == "amount", !value.isEmpty, let amountValue = BigInt(value) {
                    amount = amountValue
                } else if queryItem.name == "text", !value.isEmpty {
                    comment = value
                } else if queryItem.name == "token", !value.isEmpty {
                    token = value
                } else if queryItem.name == "bin", !value.isEmpty {
                    bin = value
                } else if queryItem.name == "jetton", !value.isEmpty {
                    jetton = value
                } else if queryItem.name == "init" || queryItem.name == "stateInit", !value.isEmpty {
                    stateInit = value
                }
            }
        }
    }
    return TonTransferUrl(address: address, amount: amount, comment: comment, token: token, bin: bin, jetton: jetton, stateInit: stateInit)
}

public func tokenDecimals(for amount: BigInt, tokenDecimals: Int, minimumSignificantDigits: Int = 2) -> Int {
    if tokenDecimals <= minimumSignificantDigits {
        return tokenDecimals
    }
    let amount = abs(amount)
    if amount < 2 {
        return tokenDecimals
    }
    let len = "\(amount)".count
    if len >= tokenDecimals + 2 {
        return max(minimumSignificantDigits, 1 + tokenDecimals - len)
    }
    var multiplier = minimumSignificantDigits
    while len + multiplier < tokenDecimals + 2 {
        multiplier += 1
    }
    return min(tokenDecimals, multiplier)
}

public func doubleToBigInt(_ doubleValue: Double, decimals: Int) -> BigInt {
    return amountValue(String(format: "%.20f", doubleValue), digits: decimals)
}

public func bigIntToDouble(amount: BigInt, decimals: Int) -> Double {
    Double.init(amount) / pow(Double(10), Double(decimals))
}

public func bigIntToDoubleString(_ amount: BigInt, decimals: Int) -> String {
    var s = String(amount)
    while s.count < decimals { s = "0" + s }
    if s.count > decimals {
        s = s.prefix(s.count - decimals) + "." + s.suffix(decimals)
    } else {
        s = "0." + s
    }
    return s
}

extension Double {
    public func rounded(decimals: Int) -> Double {
        let m = pow(10.0, Double(decimals))
        return (self * m).rounded() / m
    }
}

public func powI64(_ a: BigInt, _ b: Int) -> BigInt {
    assert(b >= 0, "b must be >= 0")
    let res: BigInt = {
        var result: BigInt = 1
        for _ in 0 ..< b {
            result = result * a
        }
        return result
    }()
    return res
}

public func convertAmount(_ tokenAmount: BigInt, price: Double, tokenDecimals: Int, baseCurrencyDecimals: Int) -> BigInt {
    tokenAmount * doubleToBigInt(price, decimals: baseCurrencyDecimals) / powI64(10, tokenDecimals)
}

public func convertAmountReverse(_ baseCurrencyAmount: BigInt, price: Double, tokenDecimals: Int, baseCurrencyDecimals: Int) -> BigInt {
    baseCurrencyAmount * powI64(10, 9) / doubleToBigInt(price, decimals: 9) * powI64(10, tokenDecimals) / powI64(10, baseCurrencyDecimals)
}

public func convertDecimalsKeepingDoubleValue(_ amount: BigInt, fromDecimals: Int, toDecimals: Int) -> BigInt {
    let delta = toDecimals - fromDecimals
    return delta >= 0 ? amount * powI64(10, delta) : amount / powI64(10, -delta)
}
