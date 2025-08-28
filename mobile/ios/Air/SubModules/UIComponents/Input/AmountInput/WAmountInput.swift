//
//  WAmountInput.swift
//  UIComponents
//
//  Created by Sina on 4/19/24.
//

import Foundation
import SwiftUI
import UIKit
import WalletContext

@MainActor
public class WAmountInput: UITextField, WThemedView {
    
    public var maximumFractionDigits: Int
    
    public var integerFont: UIFont? = nil
    public var fractionFont: UIFont? = nil
    public var error = false
    
    private let onChange: (BigInt) -> Void
    private let onFocusChange: (_ isFocused: Bool) -> ()
    
    private let useSmallerFontAtLength = 15
    private let useEvenSmallerFontAtLength = 18
    
    public init(maximumFractionDigits: Int, onChange: @escaping (BigInt) -> Void, onFocusChange: @escaping (_ isFocused: Bool) -> () = { _ in }) {
        self.maximumFractionDigits = maximumFractionDigits
        self.onChange = onChange
        self.onFocusChange = onFocusChange
        super.init(frame: .zero)
        keyboardType = .decimalPad
        autocorrectionType = .no
        spellCheckingType = .no
        if #available(iOS 18.0, *) {
            writingToolsBehavior = .none
        }
        delegate = self
        addTarget(self, action: #selector(changed), for: .editingChanged)
    }
    
    public convenience init(maximumFractionDigits: Int, onChange: @escaping () -> Void) {
        self.init(maximumFractionDigits: maximumFractionDigits, onChange: { _ in onChange() })
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public var amountInt64: BigInt {
        let formatter = NumberFormatter()
        var numberWithOutCommas = text!.replacingOccurrences(of: formatter.groupingSeparator, with: "")
        numberWithOutCommas = text!.replacingOccurrences(of: " ", with: "")
        return amountValue(numberWithOutCommas, digits: maximumFractionDigits)
    }
    
    @objc func changed() {
        onChange(self.amountInt64)
    }
    
    public func reapplyFormatting() {
        
        if let text = self.text {
            var integerFont = self.integerFont
            var fractionFont = self.fractionFont
            if text.count >= useEvenSmallerFontAtLength {
                if let f = integerFont {
                    integerFont = f.withSize(f.pointSize - 7)
                }
                if let f = fractionFont {
                    fractionFont = f.withSize(f.pointSize - 4)
                }
            } else if text.count >= useSmallerFontAtLength {
                if let f = integerFont {
                    integerFont = f.withSize(f.pointSize - 4)
                }
                if let f = fractionFont {
                    fractionFont = f.withSize(f.pointSize - 2)
                }
            }

            let at = if let attributedText {
                NSMutableAttributedString(attributedString: attributedText)
            } else {
                NSMutableAttributedString(string: text)
            }
            if let dotRange = text.range(of: ".") {
                let range1 = NSRange(text.startIndex..<dotRange.lowerBound, in: text)
                at.addAttribute(.font, value: integerFont as Any, range: range1)
                let range2 = NSRange(dotRange.lowerBound..., in: text)
                at.addAttribute(.font, value: fractionFont as Any, range: range2)
            } else {
                at.addAttribute(.font, value: integerFont as Any, range: NSRange(location: 0, length: text.count))
            }
            
            at.addAttribute(.foregroundColor, value: error ? WTheme.error : WTheme.primaryLabel, range: NSRange(location: 0, length: text.count))
            
            self.attributedText = at
        }
    }
    
    public override var intrinsicContentSize: CGSize {
        var size = super.intrinsicContentSize
        if size.width > 200 {
            size.width -= 30
        }
        return size
    }
    
    public func updateTheme() {
        reapplyFormatting()
    }
}

extension WAmountInput: UITextFieldDelegate {
    public func textField(_ textField: UITextField,
                          shouldChangeCharactersIn range: NSRange,
                          replacementString string: String) -> Bool {
        let formatter = NumberFormatter()

        let oldLength = textField.text?.count ?? 0
        // Save cursor position
        let cursorPosition = textField.offset(from: textField.beginningOfDocument, to: textField.selectedTextRange!.start)

        // support locales other than english
        var convertedInput = string.normalizeArabicPersianNumeralStringToWestern()
        if convertedInput == formatter.decimalSeparator {
            convertedInput = "."
        }
        
        // support insertion from pasteboard
        convertedInput = convertedInput.replacingOccurrences(of: " ", with: "")
        
        let newString = (textField.text! as NSString).replacingCharacters(in: range, with: convertedInput)
        /*if newString.components(separatedBy: ".")[0].count > maxLength {
            return false
        }*/

        // check if has max allowed digits after .
        if !convertedInput.isEmpty && textField.text?.contains(".") == true {
            let arr = newString.components(separatedBy: ".")
            if arr.count > 1 {
                let afterDecimalsCount = arr[1].count
                if afterDecimalsCount > maximumFractionDigits {
                    return false // can't have more digits after . !!
                }
            }
        }
        
        if convertedInput == "." {
            // do not allow . duplications
            if textField.text?.contains(".") ?? false {
                changed()
                return false // already has .
            }
            // auto add 0 if user types .
            if textField.text?.isEmpty ?? true {
                textField.text = "0."
                changed()
                return false
            }
        }

        // allow trailing 0 after . and also removing them
        if ((convertedInput == "0" || convertedInput == "") && (textField.text! as NSString).range(of: ".").location < range.location) {
            if oldLength >= useSmallerFontAtLength - 1 {
                reapplyFormatting()
            }
            return true
        }

        // First check whether the replacement string's numeric...
        let cs = NSCharacterSet(charactersIn: "0123456789.").inverted
        let filtered = convertedInput.components(separatedBy: cs)
        let component = filtered.joined(separator: "")
        let isNumeric = convertedInput == component

        // Then if the replacement string's numeric, or if it's
        // a backspace, or if it's a decimal point and the text
        // field doesn't already contain a decimal point,
        // reformat the new complete number using
        if isNumeric {
            let numberWithoutSpacing = newString.replacingOccurrences(of: " ", with: "")
            
            if numberWithoutSpacing.isEmpty {
                textField.text = numberWithoutSpacing
            } else {
                let parts = numberWithoutSpacing.components(separatedBy: ".")
                if let num = BigInt(parts[0]) {
                    textField.text = formatBigIntText(num, tokenDecimals: 0, decimalsCount: 0)
                }
                if parts.count > 1 {
                    textField.text = "\(textField.text!).\(parts[1])"
                }
            }
        }

        // reapply smaller font to fraction
        self.reapplyFormatting()
        
        // Restore cursor position
        var cursorOffset = 0
        if string.count == 0,
           (textField.text ?? "").count > cursorPosition,
           textField.text![textField.text!.index(textField.text!.startIndex, offsetBy: cursorPosition)]  == "." {
            // removed a dot
            cursorOffset = 1
        }
        if string.count == 0, (textField.text?.count ?? 0 == oldLength) {
            // backspaced a sapce
            cursorOffset = -1
        }
        if let newPosition = textField.position(from: textField.beginningOfDocument,
                                                offset: cursorPosition + (textField.text?.count ?? 0) - oldLength + max(0, string.count - 1) + cursorOffset) {
            textField.selectedTextRange = textField.textRange(from: newPosition, to: newPosition)
        }

        changed()
        return false
    }
    
    public func textFieldDidBeginEditing(_ textField: UITextField) {
        self.reapplyFormatting()
        onFocusChange(true)
    }

    public func textFieldDidEndEditing(_ textField: UITextField) {
        self.reapplyFormatting()
        onFocusChange(false)
    }
}


@MainActor
public struct WUIAmountInput: UIViewRepresentable {
    
    @Binding public var amount: BigInt?
    @Binding public var isFocused: Bool
    
    public var maximumFractionDigits: Int
    public let font: UIFont?
    public let fractionFont: UIFont?
    public let alignment: NSTextAlignment?
    public var error: Bool
    
    @State private var cooldown: Date = .distantPast
    
    public init(amount: Binding<BigInt?>, maximumFractionDigits: Int, font: UIFont? = nil, fractionFont: UIFont? = nil, alignment: NSTextAlignment? = nil, isFocused: Binding<Bool>, error: Bool) {
        self._amount = amount
        self.maximumFractionDigits = maximumFractionDigits
        self.font = font
        self.fractionFont = fractionFont
        self.alignment = alignment
        self._isFocused = isFocused
        self.error = error
    }
    
    public final class Coordinator {
        var forceFirstResponder = false
    }
    
    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    public func makeUIView(context: Context) -> WAmountInput {
        let view = WAmountInput(
            maximumFractionDigits: maximumFractionDigits,
            onChange: { v in
                DispatchQueue.main.async {
                    amount = v
                }
            },
            onFocusChange: { isFocused in
                DispatchQueue.main.async {
                    self.isFocused = isFocused
                    if !isFocused {
                        cooldown = .now
                    }
                }
            }
        )
        view.placeholder = "0"
        view.font = font
        view.integerFont = font
        view.fractionFont = fractionFont
        if let alignment {
            view.textAlignment = alignment
        }
        if isFocused {
            context.coordinator.forceFirstResponder = true
        }
        return view
    }
    
    public func updateUIView(_ view: WAmountInput, context: Context) {
        view.maximumFractionDigits = maximumFractionDigits
        if (amount ?? 0) != view.amountInt64 {
            let s = formatBigIntText(amount ?? 0,
                                     currency: nil,
                                     negativeSign: false,
                                     tokenDecimals: maximumFractionDigits,
                                     decimalsCount: maximumFractionDigits,
                                     forceCurrencyToRight: false,
                                     roundUp: false)
            _ = view.textField(view, shouldChangeCharactersIn: NSRange(location: 0, length: view.text?.count ?? 0), replacementString: s)
            view.reapplyFormatting()
        }
        if view.canBecomeFirstResponder && context.coordinator.forceFirstResponder {
            view.becomeFirstResponder()
            context.coordinator.forceFirstResponder = false
        } else if isFocused && !view.isFirstResponder {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                if Date().timeIntervalSince(cooldown) > 0.2 { // make sure kb doesn't reappear when navigating away from screen
                    let ok = view.becomeFirstResponder()
                    if !ok {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1)  {
                            isFocused = false
                        }
                    }
                }
            }
        } else if !isFocused && view.isFirstResponder {
            let ok = view.resignFirstResponder()
            if !ok {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1)  {
                    isFocused = true
                }
            }
        }
        if error != view.error {
            view.error = error
            view.reapplyFormatting()
        }
    }
    
    public func sizeThatFits(_ proposal: ProposedViewSize, uiView: WAmountInput, context: Context) -> CGSize? {
        switch proposal.width {
        case 0, nil:
            var size = uiView.intrinsicContentSize
            size.width = max(20, size.width)
            return size
        case .infinity:
            return CGSize(width: .infinity, height: uiView.intrinsicContentSize.height)
        case .some(let width):
            var size = uiView.sizeThatFits(.init(width: width, height: .infinity))
            size.width = max(20, width)
            return size
        }

    }
}
