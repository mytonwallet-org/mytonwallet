//
//  PasscodeOptionsView.swift
//  UIPasscode
//
//  Created by Sina on 4/17/23.
//

import UIKit
import UIComponents
import WalletContext

protocol PasscodeOptionsViewDelegate: AnyObject {
    func passcodeOptionsDigitSelected(digits: Int)
}

class PasscodeOptionsView: UIStackView {

    weak var delegate: PasscodeOptionsViewDelegate? = nil

    private(set) var visibility = false {
        didSet {
            UIView.animate(withDuration: 0.5) {
                self.alpha = self.visibility ? 1 : 0
            }
        }
    }

    init(delegate: PasscodeOptionsViewDelegate) {
        super.init(frame: CGRect.zero)
        setupView(delegate: delegate)
    }
    
    override init(frame: CGRect) {
        fatalError()
    }
    
    required init(coder: NSCoder) {
        fatalError()
    }

    private func setupView(delegate: PasscodeOptionsViewDelegate) {
        self.delegate = delegate

        translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 250)
        ])

        axis = .vertical

        alpha = visibility ? 1 : 0

        // 4-digit button
        let fourDigitButton = UIButton(type: .system)
        fourDigitButton.translatesAutoresizingMaskIntoConstraints = false
        fourDigitButton.setTitle(lang("Use 4-digit Passcode"), for: .normal)
        fourDigitButton.tintColor = WTheme.primaryLabel
        fourDigitButton.titleLabel?.textAlignment = .left
        fourDigitButton.titleLabel?.font = UIFont.systemFont(ofSize: 17)
        NSLayoutConstraint.activate([
            fourDigitButton.heightAnchor.constraint(equalToConstant: 40)
        ])
        fourDigitButton.addTarget(self, action: #selector(fourDigitPressed), for: .touchUpInside)
        addArrangedSubview(fourDigitButton)
        
        // separator
        let separator = UIView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = WTheme.separator
        NSLayoutConstraint.activate([
            separator.heightAnchor.constraint(equalToConstant: 0.33)
        ])
        addArrangedSubview(separator)

        // 6-digit button
        let sixDigitButton = UIButton(type: .system)
        sixDigitButton.translatesAutoresizingMaskIntoConstraints = false
        sixDigitButton.tintColor = WTheme.primaryLabel
        sixDigitButton.titleLabel?.textAlignment = .left
        sixDigitButton.setTitle(lang("Use 6-digit Passcode"), for: .normal)
        sixDigitButton.titleLabel?.font = UIFont.systemFont(ofSize: 17)
        NSLayoutConstraint.activate([
            sixDigitButton.heightAnchor.constraint(equalToConstant: 40)
        ])
        sixDigitButton.addTarget(self, action: #selector(sixDigitPressed), for: .touchUpInside)
        addArrangedSubview(sixDigitButton)
        // six-digit option is disabled
        sixDigitButton.isHidden = true
    }
    
    @objc func fourDigitPressed(_ sender: UIButton) {
        delegate?.passcodeOptionsDigitSelected(digits: 4)
        toggle()
    }

    @objc func sixDigitPressed(_ sender: UIButton) {
        delegate?.passcodeOptionsDigitSelected(digits: 6)
        toggle()
    }
    
    func toggle() {
        visibility = !visibility
    }
    
    // add shadow layer
    private var shadowLayer: CAShapeLayer!
    override func layoutSubviews() {
        super.layoutSubviews()

        if shadowLayer == nil {
            shadowLayer = CAShapeLayer()
            shadowLayer.path = UIBezierPath(roundedRect: bounds, cornerRadius: 13).cgPath
            shadowLayer.fillColor = UIColor.white.cgColor

            shadowLayer.shadowColor = UIColor.black.cgColor
            shadowLayer.shadowPath = shadowLayer.path
            shadowLayer.shadowOffset = CGSize(width: 0, height: 4.0)
            shadowLayer.shadowOpacity = 0.2
            shadowLayer.shadowRadius = 48

            layer.insertSublayer(shadowLayer, at: 0)
        }
    }
}
