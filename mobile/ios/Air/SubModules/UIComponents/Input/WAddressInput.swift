//
//  WAddressInput.swift
//  UIComponents
//
//  Created by Sina on 5/12/24.
//

import SwiftUI
import UIKit
import WalletContext

public class WAddressInput: UIView {
    
    // MARK: - Properties
    
    public var textChanged: ((String) -> Void)?
    public var onFocusChange: ((Bool) -> Void)?
    public var onPastePressed: (() -> Void)?
    public var onScanPressed: (() -> Void)?
    
    // MARK: - Initialization
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - UI Setup
    
    public lazy var textView: UITextView = {
        let tv = UITextView()
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.font = .systemFont(ofSize: 17)
        tv.textContainerInset = UIEdgeInsets(top: 11, left: 16, bottom: 11, right: 16)
        tv.textContainer.lineBreakMode = .byCharWrapping
        return tv
    }()
    
    private lazy var textFieldOptionsView: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        let pasteButton = UIButton(type: .system)
        pasteButton.setTitle("Paste", for: .normal)
        pasteButton.titleLabel?.font = .systemFont(ofSize: 17)
        pasteButton.addTarget(self, action: #selector(pastePressed), for: .touchUpInside)
        pasteButton.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(pasteButton)
        let scanButton = UIButton(type: .system)
        scanButton.setImage(UIImage(named: "ScanIcon", in: AirBundle, compatibleWith: nil)?.withRenderingMode(.alwaysTemplate), for: .normal)
        scanButton.addTarget(self, action: #selector(scanPressed), for: .touchUpInside)
        scanButton.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(scanButton)
        
        NSLayoutConstraint.activate([
            pasteButton.trailingAnchor.constraint(equalTo: scanButton.leadingAnchor, constant: -12),
            pasteButton.centerYAnchor.constraint(equalTo: v.centerYAnchor),
            scanButton.centerYAnchor.constraint(equalTo: v.centerYAnchor),
            pasteButton.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            scanButton.trailingAnchor.constraint(equalTo: v.trailingAnchor)
        ])
        
        return v
    }()
    
    private var placeholderLabel: UILabel = {
        // placeholder
        let lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        return lbl
    }()
    
    private func setupViews() {
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = 12
        layer.masksToBounds = true

        addSubview(textView)
        textView.delegate = self
        NSLayoutConstraint.activate([
            textView.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            textView.topAnchor.constraint(equalTo: topAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor),
            textView.leadingAnchor.constraint(equalTo: leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])

        addSubview(textFieldOptionsView)
        NSLayoutConstraint.activate([
            textFieldOptionsView.rightAnchor.constraint(equalTo: rightAnchor, constant: -10),
            textFieldOptionsView.centerYAnchor.constraint(equalTo: textView.centerYAnchor)
        ])
        
        addSubview(placeholderLabel)
        NSLayoutConstraint.activate([
            placeholderLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            placeholderLabel.topAnchor.constraint(equalTo: topAnchor, constant: 11)
        ])
        
    }
    
    // MARK: - Actions
    
    @objc private func pastePressed() {
        if let onPastePressed {
            onPastePressed()
        } else if let pasteboardString = UIPasteboard.general.string {
            textView.text = pasteboardString
            textViewDidChange(textView)
            resignFirstResponder()
        }
    }
    
    @objc private func scanPressed() {
        onScanPressed?()
    }
    
    public var attributedPlaceholder: NSAttributedString? = nil {
        didSet {
            placeholderLabel.attributedText = attributedPlaceholder
        }
    }
}

extension WAddressInput: UITextViewDelegate {
    public func textViewDidChange(_ textView: UITextView) {
        textChanged?(textView.text)
        textFieldOptionsView.isHidden = !textView.text.isEmpty
        placeholderLabel.isHidden = !textView.text.isEmpty
    }
    
    public func textViewDidBeginEditing(_ textField: UITextView) {
        onFocusChange?(true)
    }

    public func textViewDidEndEditing(_ textField: UITextView) {
        onFocusChange?(false)
    }
}

