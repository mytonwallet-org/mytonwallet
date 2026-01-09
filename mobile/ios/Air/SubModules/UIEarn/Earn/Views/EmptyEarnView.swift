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

private let stickerSize: CGFloat = 120

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
    
    private var sticker: WAnimatedSticker = {
        let sticker = WAnimatedSticker()
        sticker.animationName = "duck_wait"
        sticker.setup(width: Int(stickerSize), height: Int(stickerSize), playbackMode: .once)
        sticker.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            sticker.widthAnchor.constraint(equalToConstant: stickerSize),
            sticker.heightAnchor.constraint(equalToConstant: stickerSize),
        ])
        return sticker
    }()
    
    private lazy var earnFromTokensLabel = {
        let lbl = UILabel()
        lbl.font = .systemFont(ofSize: 17)
        lbl.text = lang("Earn from your tokens while holding them", arg1: config.baseToken.symbol)
        lbl.textAlignment = .center
        lbl.numberOfLines = 0
        return lbl
    }()
    
    lazy var estimatedAPYLabel = {
        let lbl = UILabel()
        lbl.font = .systemFont(ofSize: 16)
        lbl.text = ""
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
        addArrangedSubview(sticker)
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
