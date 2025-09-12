//
//  WStrings.swift
//  WalletContext
//
//  Created by Sina on 3/16/24.
//

import Foundation

public enum WStrings {
    
    public static func WordCheck_ViewWords(wordIndices: [Int]) -> String {
        return fillValues(lang("Let’s check that you wrote them down correctly. Please enter the words %1$@, %2$@ and %3$@."), values: wordIndices.map({ i in
            return "\(i + 1)"
        }))
    }

    public static func SetPasscode_Text(digits: Int) -> String {
        return fillValues(lang("Enter the %1$@ digits in the passcode."), values: ["\(digits)"])
    }
    public static func ConfirmPasscode_Text(digits: Int) -> String {
        return fillValues(lang("Re-enter the %1$@ digits in the passcode."), values: ["\(digits)"])
    }
    
    public static func InsufficientBalance_Text(symbol: String) -> String {
        return fillValues(lang("Insufficient %1$@ Balance"), values: [symbol])
    }
    
    public static func Send_AuthorizeDiesel_Text(symbol: String) -> String {
        return fillValues(lang("Authorize %1$@ fee"),
                          values: [symbol])
    }
    
    public static func ConfirmAmountAndAddress_Text(amountString: String, address: String) -> String {
        return fillValues(lang("%1$@ to %2$@"),
                          values: [amountString, address])
    }
    
    public static func Swap_PricePer_Text(symbol: String) -> String {
        return fillValues(lang("Price per 1 %1$@"),
                          values: [symbol])
    }
    
    public static func Swap_InsufficientBalance_Text(symbol: String) -> String {
        return fillValues(lang("Insufficient %1$@ Balance"),
                          values: [symbol])
    }
    
    public static func Swap_Submit_Text(from: String, to: String) -> String {
        return fillValues(lang("Swap %1$@ to %2$@"),
                          values: [from, to])
    }

    public static func Swap_ConfirmSubtitle_Text(from: String, to: String) -> String {
        return fillValues(lang("%1$@ to %2$@"),
                          values: [from, to])
    }
    
    public static func Swap_AuthorizeDiesel_Text(symbol: String) -> String {
        return fillValues(lang("Authorize %1$@ fee"),
                          values: [symbol])
    }
    
    public static func CrossChainSwap_EnterChainAddress_Text(symbol: String) -> String {
        return fillValues(lang("Enter %1$@ address"), values: [symbol])
    }
    
    public static func CrossChainSwap_SendToThisAddress_Text(symbol: String) -> String {
        return fillValues(lang("Send %1$@ to this address"), values: [symbol])
    }
        
    public static func fillValues(_ format: String, values: [String]) -> String {
        var result = format
        for (index, value) in values.enumerated() {
            result = result.replacingOccurrences(of: "%\(index + 1)$@", with: value)
        }
        return result
    }

    private static func fillValues(_ format: String,
                                   textAttr: [NSAttributedString.Key: Any],
                                   values: [NSAttributedString]) -> NSMutableAttributedString {
        var formatString = format
        let result = NSMutableAttributedString()
        for (index, value) in values.enumerated() {
            if let valueRange = formatString.range(of: "%\(index + 1)$@") {
                // the string before format value
                let stringBeforeValue = String(formatString[..<valueRange.lowerBound])
                formatString = String(formatString[valueRange.upperBound...])
                result.append(NSAttributedString(string: String(stringBeforeValue)))
                // value
                result.append(value)
            }
        }
        return result
    }

}
