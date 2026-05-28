//
//  WWordInput.swift
//  UIComponents
//
//  Created by Sina on 4/14/23.
//

import UIKit
import WalletContext

public protocol WWordInputDelegate: AnyObject {
    func wordInputDidWantToCommitData(_ input: WWordInput)
    func wordInputDidBeginEditing(_ input: WWordInput)
    func textChanged()
    func wordInput(_ input: WWordInput, wantsPasteWords words: [String])
}

public class WWordInput: UIView {
    private weak var suggestionsView: WSuggestionsView? = nil
    private weak var delegate: WWordInputDelegate? = nil
    
    public let wordNumber: Int
    public var advancesOnSuggestionSelection = true
    public weak var nextInput: WWordInput?

    private let numberLabel = UILabel()
    
    public init(wordNumber: Int, suggestionsView: WSuggestionsView?, delegate: WWordInputDelegate?) {
        self.wordNumber = wordNumber
        self.suggestionsView = suggestionsView
        self.delegate = delegate
        
        super.init(frame: CGRect.zero)
        
        setup()
    }
    
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public lazy var textField = WWordInputField(input: self)

    func setup() {
        translatesAutoresizingMaskIntoConstraints = false

        // corner radius
        layer.cornerRadius = 10

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(focusTextField)))

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
        numberLabel.isAccessibilityElement = false
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
        textField.accessibilityLabel = "\(wordNumber)"
        stackView.addArrangedSubview(textField)

        updateTheme()
    }

    private func updateTheme() {
        backgroundColor = .air.sheetBackground
        numberLabel.textColor = .air.secondaryLabel
    }
    
    @objc private func focusTextField() {
        textField.becomeFirstResponder()
    }

    private func showSuggestions(for keyword: String?) {
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

    public func setText(_ text: String, notifyDelegate: Bool, goToNextInput: Bool) {
        textField.text = text
        if notifyDelegate {
            delegate?.textChanged()
        }
        textFieldDidEndEditing(textField)
        
        if goToNextInput {
            nextInput?.textField.becomeFirstResponder()
        }
    }
        
    internal func paste(words: [String]) {
        delegate?.wordInput(self, wantsPasteWords: words)
    }
    
    public var trimmedText: String? {
        textField.text?.trimmingCharacters(in: .whitespaces).lowercased().nilIfEmpty
    }
}

extension WWordInput: UITextFieldDelegate {
    public func textFieldDidBeginEditing(_ textField: UITextField) {
        textField.textColor = UIColor.label
        if let txt = trimmedText, !txt.isEmpty {
            showSuggestions(for: txt)
        }
        delegate?.wordInputDidBeginEditing(self)
    }
    
    public func textFieldShouldClear(_ textField: UITextField) -> Bool {
        textField.text = nil
        showSuggestions(for: nil)
        delegate?.textChanged()
        return false
    }

    public func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if let nextInput {
            nextInput.textField.becomeFirstResponder()
        } else {
            delegate?.wordInputDidWantToCommitData(self)
        }
        return false
    }
    
    public func textFieldDidEndEditing(_ textField: UITextField) {
        let keyword = trimmedText ?? ""
        if isValidPrivateKeyHex(keyword) {
            textField.textColor = UIColor.label
            showSuggestions(for: nil)
            return
        }
        if !possibleWordList.contains(keyword) {
            if !keyword.isEmpty, let suggestion = possibleWordList.first(where: { txt in
                txt.starts(with: keyword)
            }) {
                textField.text = suggestion
                textField.textColor = UIColor.label
            } else {
                textField.textColor = .air.error
            }
        } else {
            textField.textColor = UIColor.label
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
    return WWordInput(wordNumber: 2, suggestionsView: nil, delegate: nil)
}
#endif
