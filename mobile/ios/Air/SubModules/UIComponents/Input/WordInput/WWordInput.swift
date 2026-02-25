//
//  WWordInput.swift
//  UIComponents
//
//  Created by Sina on 4/14/23.
//

import UIKit
import WalletContext

public protocol WWordInputDelegate: AnyObject {
    func resignedFirstResponder()
    func textChanged()
}

public class WWordInput: UIView {
    private var wordNumber: Int = 0
    private weak var suggestionsView: WSuggestionsView? = nil
    private weak var delegate: WWordInputDelegate? = nil
    public init(index: Int,
                wordNumber: Int,
                suggestionsView: WSuggestionsView?,
                delegate: WWordInputDelegate?) {
        self.wordNumber = wordNumber
        self.suggestionsView = suggestionsView
        self.delegate = delegate
        super.init(frame: CGRect.zero)
        self.tag = index
        setup()
    }
    
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    let numberLabel = UILabel()
    public lazy var textField = WWordInputField(input: self)
    
    public var nextInput: WWordInput? {
        return superview?.superview?.viewWithTag(tag + 1) as? WWordInput
    }

    func setup() {
        translatesAutoresizingMaskIntoConstraints = false

        // corner radius
        layer.cornerRadius = 10

        // We had to wrap UIStackView inside a UIView to be able to set backgroundColor on WWordInput on older iOS versions;
        //  Because, prior to iOS 14, stack views were "non-rendering" views
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.spacing = 6
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leftAnchor.constraint(equalTo: leftAnchor),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.rightAnchor.constraint(equalTo: rightAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
            stackView.heightAnchor.constraint(equalToConstant: 50)
        ])

        // add word number label
        numberLabel.translatesAutoresizingMaskIntoConstraints = false
        numberLabel.text = "\(wordNumber)"
        numberLabel.textAlignment = .right
        stackView.addArrangedSubview(numberLabel)
        NSLayoutConstraint.activate([
            numberLabel.widthAnchor.constraint(equalToConstant: 42)
        ])
        
        // add text field
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.autocorrectionType = .no
        textField.spellCheckingType = .no
        textField.backgroundColor = .clear
        textField.delegate = self
        textField.clearButtonMode = .whileEditing
        textField.inputAccessoryView = suggestionsView
        stackView.addArrangedSubview(textField)

        updateTheme()
    }

    func updateTheme() {
        backgroundColor = WTheme.wordInput.background
        numberLabel.textColor = WTheme.secondaryLabel
    }
    
    func showSuggestions(for keyword: String?) {
        guard let keyword, !keyword.isEmpty else {
            suggestionsView?.config(activeInput: nil, suggestions: [])
            return
        }
        var suggestions = Array(possibleWordList.filter { txt in
            txt.starts(with: keyword)
        })
        if suggestions.count == 1 && keyword == suggestions[0] {
            suggestions = []
        }
        suggestionsView?.config(activeInput: self, suggestions: suggestions)
    }
    
    public var trimmedText: String? {
        textField.text?.trimmingCharacters(in: .whitespaces).lowercased().nilIfEmpty
    }
}

extension WWordInput: UITextFieldDelegate {
    public func textFieldDidBeginEditing(_ textField: UITextField) {
        textField.textColor = WTheme.primaryLabel
        if let txt = trimmedText, !txt.isEmpty {
            showSuggestions(for: txt)
        }
    }
    public func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if let nextField = superview?.superview?.viewWithTag(tag + 1) as? WWordInput {
            nextField.textField.becomeFirstResponder()
        } else {
            textField.resignFirstResponder()
            delegate?.resignedFirstResponder()
        }
        return false
    }
    public func textFieldDidEndEditing(_ textField: UITextField) {
        let keyword = trimmedText ?? ""
        if isValidPrivateKeyHex(keyword) {
            textField.textColor = WTheme.primaryLabel
            showSuggestions(for: nil)
            return
        }
        if !possibleWordList.contains(keyword) {
            if !keyword.isEmpty, let suggestion = possibleWordList.first(where: { txt in
                txt.starts(with: keyword)
            }) {
                textField.text = suggestion
                textField.textColor = WTheme.primaryLabel
            } else {
                textField.textColor = WTheme.error
            }
        } else {
            textField.textColor = WTheme.primaryLabel
        }
        showSuggestions(for: nil)
    }
    public func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        defer { delegate?.textChanged() }
        if let text = textField.text,
           let textRange = Range(range, in: text) {
            let newText = text.replacingCharacters(in: textRange, with: string).trimmingCharacters(in: .whitespaces).lowercased()
            showSuggestions(for: newText)
            if textField.text != newText {
                let cursorOffset = range.location + string.count
                
                textField.text = newText
                
                if let newPosition = textField.position(from: textField.beginningOfDocument, offset: min(cursorOffset, newText.count)) {
                    textField.selectedTextRange = textField.textRange(from: newPosition, to: newPosition)
                }
                
                return false
            }
        }
        return true
    }
}

#if DEBUG
@available(iOS 17.0, *)
#Preview {
    return WWordInput(index: 0, wordNumber: 2, suggestionsView: nil, delegate: nil)
}
#endif
