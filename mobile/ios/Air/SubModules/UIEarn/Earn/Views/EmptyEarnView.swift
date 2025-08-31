//
//  EmptyEarnView.swift
//  UIEarn
//
//  Created by Sina on 5/13/24.
//

import SwiftUI
import UIKit
import UIComponents
import WalletContext

public class EmptyEarnView: WTouchPassStackView, WThemedView {
    
    let config: StakingConfig
    
    public init(config: StakingConfig) {
        self.config = config
        super.init(frame: .zero)
        setupViews()
    }
    
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private let notFoundImageView = {
        let iv = UIImageView(image: UIImage(named: "EarnNotFound", in: AirBundle, compatibleWith: nil))
        return iv
    }()
    
    private let earnFromTokensLabel = {
        let lbl = UILabel()
        lbl.font = .systemFont(ofSize: 17)
        lbl.text = lang("Earn from your tokens\nwhile holding them")
        lbl.textAlignment = .center
        lbl.numberOfLines = 0
        return lbl
    }()
    
    let estimatedAPYLabel = {
        let lbl = UILabel()
        lbl.font = .systemFont(ofSize: 16)
        lbl.text = lang("Estimated APY")
        lbl.textAlignment = .center
        lbl.numberOfLines = 0
        return lbl
    }()
    
    private lazy var whyThisIsSafeButton = {
        let button = WButton(style: .clearBackground)
        button.setTitle(config.explainTitle, for: .normal)
        button.addTarget(self, action: #selector(self.whyThisIsSafePressed), for: .touchUpInside)
        return button
    }()
    
    private func setupViews() {
        spacing = 16
        axis = .vertical
        alignment = .center
        addArrangedSubview(notFoundImageView)
        addArrangedSubview(earnFromTokensLabel)
        addArrangedSubview(estimatedAPYLabel)
        addArrangedSubview(whyThisIsSafeButton)
        updateTheme()
    }
    
    public func updateTheme() {
        estimatedAPYLabel.textColor = WTheme.secondaryLabel
    }
    
    @objc func whyThisIsSafePressed() {
        showWhyIsSafe(config: config)
    }
    
}
