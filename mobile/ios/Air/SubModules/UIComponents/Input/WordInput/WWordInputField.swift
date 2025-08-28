//
//  WWordInputField.swift
//  UIComponents
//
//  Created by Sina on 7/1/24.
//

import UIKit

public class WWordInputField: UITextField {
    
    private weak var input: WWordInput? = nil
    public init(input: WWordInput) {
        self.input = input
        super.init(frame: .zero)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func paste(_ sender: Any?) {
        guard let pasteboardString = UIPasteboard.general.string else {
            super.paste(sender)
            return
        }
        
        let words = pasteboardString.split { $0 == "," || $0 == " " || $0.isNewline }.map(String.init).filter { it in
            !it.isEmpty
        }
        distributeWords(words)
    }
    
    public func distributeWords(_ words: [String]) {
        var currentTextField: WWordInputField? = self
        for (i, word) in words.enumerated() {
            currentTextField?.text = word
            currentTextField?.delegate?.textFieldDidEndEditing?(currentTextField!)
            if i < words.count - 1 {
                currentTextField = currentTextField?.input?.nextInput?.textField
            }
        }
        _ = currentTextField?.input?.textFieldShouldReturn(currentTextField!)
    }
}
