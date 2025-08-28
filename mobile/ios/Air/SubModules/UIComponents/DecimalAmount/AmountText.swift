
import Foundation
import SwiftUI
import WalletCore
import WalletContext


extension SwiftUI.Text {
    public init<Backing: DecimalBackingType>(amount: DecimalAmount<Backing>, format: DecimalAmountFormatStyle<Backing>) {
        self = Text(format.format(amount))
    }
}


public struct AmountText<Backing: DecimalBackingType>: View {
    
    public var amount: DecimalAmount<Backing>
    public var format: DecimalAmountFormatStyle<Backing>
    
    public var integerFont: UIFont
    public var fractionFont: UIFont
    public var symbolFont: UIFont
    public var integerColor: UIColor
    public var fractionColor: UIColor
    public var symbolColor: UIColor
    public var forceSymbolColor: Bool
    
    public init(
        amount: DecimalAmount<Backing>,
        format: DecimalAmountFormatStyle<Backing>,
        integerFont: UIFont,
        fractionFont: UIFont,
        symbolFont: UIFont,
        integerColor: UIColor,
        fractionColor: UIColor,
        symbolColor: UIColor,
        forceSymbolColor: Bool = false,
    ) {
        self.amount = amount
        self.format = format
        self.integerFont = integerFont
        self.fractionFont = fractionFont
        self.symbolFont = symbolFont
        self.integerColor = integerColor
        self.fractionColor = fractionColor
        self.symbolColor = symbolColor
        self.forceSymbolColor = forceSymbolColor
    }
    
    public var body: some View {
        Text(amount.formatAttributed(format: format, integerFont: integerFont, fractionFont: fractionFont, symbolFont: symbolFont, integerColor: integerColor, fractionColor: fractionColor, symbolColor: symbolColor, forceSymbolColor: forceSymbolColor))
    }
}


extension DecimalAmount {
    
    public func formatAttributed(
        format: DecimalAmountFormatStyle<Backing>,
        integerFont: UIFont,
        fractionFont: UIFont,
        symbolFont: UIFont,
        integerColor: UIColor,
        fractionColor: UIColor,
        symbolColor: UIColor,
        forceSymbolColor: Bool = false,
    ) -> NSAttributedString {
        let string = format.format(self)
        let len = (string as NSString).length
        let at = NSMutableAttributedString(string: string)
        
        let symbolRange = (string as NSString).range(of: symbol ?? "???")
        
        let numberRange: NSRange = if symbolRange.location == NSNotFound {
            NSRange(location: 0, length: len)
        } else if symbolRange.location == 0 {
            NSRange(location: symbolRange.upperBound, length: len - symbolRange.upperBound)
        } else {
            NSRange(location: 0, length: symbolRange.lowerBound)
        }
        
        let dotRange = (string as NSString).range(of: ".", range: numberRange)
        
        let integerRange: NSRange = {
            let lo = if symbolRange.location == 0 {
                symbolRange.upperBound
            } else {
                0
            }
            let hi = if dotRange.location != NSNotFound {
                dotRange.location
            } else if symbolRange.location != NSNotFound, symbolRange.location > 0 {
                symbolRange.location
            } else {
                len
            }
            return NSRange(location: lo, length: hi - lo)
        }()
        
        let fractionRange: NSRange = {
            if dotRange.location == NSNotFound {
                return NSRange(location: NSNotFound, length: 0)
            }
            let lo = dotRange.lowerBound
            // if symbol is at the end, show it in fraction font
            let hi = len
            return NSRange(location: lo, length: hi - lo)
        }()
        
        at.addAttributes([
            .foregroundColor: integerColor,
            .font: integerFont
        ], range: integerRange)
        
        if fractionRange.location != NSNotFound {
            at.addAttributes([
                .foregroundColor: fractionColor,
                .font: fractionFont
            ], range: fractionRange)
        }
        
        // only use special symbol font if at the start
        if symbolRange.location != NSNotFound && (symbolRange.location == 0 || forceSymbolColor) {
            at.addAttributes([
                .foregroundColor: symbolColor,
                .font: symbolFont
            ], range: symbolRange)
        } else if symbolRange.location != NSNotFound && fractionRange.location == NSNotFound {
            at.addAttributes([
                .foregroundColor: fractionColor,
                .font: fractionFont
            ], range: symbolRange)
        }
        return at
    }
}
