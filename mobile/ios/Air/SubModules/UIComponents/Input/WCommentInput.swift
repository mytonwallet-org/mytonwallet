//
//  WCommentInput.swift
//  UIComponents
//
//  Created by Sina on 5/9/24.
//

import UIKit
import WalletContext

public protocol WCommentInputDelegate: AnyObject {
    func commentTextChanged(newHeight: CGFloat)
}

public class WCommentInput: UITextView {
    
    public weak var commentDelegate: WCommentInputDelegate?
    public init(delegate: WCommentInputDelegate?) {
        self.commentDelegate = delegate
        super.init(frame: .zero, textContainer: nil)
        setup()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public var placeholderLabel: UILabel!
    
    public override func awakeFromNib() {
        super.awakeFromNib()
        setup()
    }
    
    public override func prepareForInterfaceBuilder() {
        super.prepareForInterfaceBuilder()
        setup()
    }
    
    private var heightConstraint: NSLayoutConstraint!
    
    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        heightConstraint = heightAnchor.constraint(equalToConstant: 44)
        NSLayoutConstraint.activate([
            heightConstraint,
        ])

        delegate = self

        layer.cornerRadius = 12
        font = .systemFont(ofSize: 17, weight: .regular)
        
        // setup placeholder
        placeholderLabel = UILabel()
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.font = font
        addSubview(placeholderLabel)
        NSLayoutConstraint.activate([
            placeholderLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            placeholderLabel.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            placeholderLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            placeholderLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: 14),
        ])
        
        textContainerInset = UIEdgeInsets(top: 14, left: 12, bottom: 14, right: 12)

        // set theme colors
        updateTheme()
    }
    
    func updateTheme() {
        backgroundColor = WTheme.groupedItem
        textColor = WTheme.primaryLabel
        placeholderLabel.textColor = WTheme.secondaryLabel
    }

}

extension WCommentInput: UITextViewDelegate {
    public func textViewDidChange(_ textView: UITextView) {
        // show exceeded text in red
        if text.count > walletTextLimit {
            let attr = NSMutableAttributedString(string: String(text.prefix(walletTextLimit)), attributes: [
                NSAttributedString.Key.font: UIFont.systemFont(ofSize: 17, weight: .regular),
                NSAttributedString.Key.foregroundColor: textColor ?? WTheme.primaryLabel
            ])
            attr.append(NSAttributedString(string: String(text.suffix(text.count - walletTextLimit)), attributes: [
                NSAttributedString.Key.font: UIFont.systemFont(ofSize: 17, weight: .regular),
                NSAttributedString.Key.backgroundColor: WTheme.error.withAlphaComponent(0.12),
                NSAttributedString.Key.foregroundColor: WTheme.error
            ]))
            attributedText = attr
        } else {
            textColor = WTheme.primaryLabel
            text = textView.text
        }

        // set placeholder visibility
        placeholderLabel.isHidden = !textView.text.isEmpty

        // set height
        heightConstraint.constant = max(44, textView.contentSize.height)
        layoutIfNeeded()

        commentDelegate?.commentTextChanged(newHeight: heightConstraint.constant)
    }
}
