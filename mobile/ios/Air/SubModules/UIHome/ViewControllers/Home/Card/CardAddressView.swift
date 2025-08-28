
import Foundation
import UIKit
import SwiftUI
import UIComponents
import WalletCore
import WalletContext
import Popovers


final class CardAddressView: UIButton {
    
    private let chainIcon = UIImageView()
    let label = UILabel()
    private let chevron = UIImageView()
    
    let walletAddressPadding: CGFloat = 11 // increase touch target
    private var walletChainIconWidthConstraint: NSLayoutConstraint!
    private var chevronSpacingConstraint: NSLayoutConstraint!
    
    
    convenience init() {
        self.init(configuration: .plain(), primaryAction: nil)
        setup()
    }
    
    func setup() {
        
        self.translatesAutoresizingMaskIntoConstraints = false
        self.showsMenuAsPrimaryAction = false
        self.configuration?.contentInsets = .zero
        
        chainIcon.translatesAutoresizingMaskIntoConstraints = false
        chainIcon.layer.masksToBounds = true
        walletChainIconWidthConstraint = chainIcon.widthAnchor.constraint(equalToConstant: 16)
        NSLayoutConstraint.activate([
            walletChainIconWidthConstraint,
            chainIcon.heightAnchor.constraint(equalToConstant: 16),
        ])
        
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .white
        label.alpha = 0.75
        
        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.layer.masksToBounds = true
        chevron.image = .airBundle("ChevronDown10")
        chevron.tintColor = .white
        NSLayoutConstraint.activate([
            chevron.widthAnchor.constraint(equalToConstant: 10),
            chevron.heightAnchor.constraint(equalToConstant: 10),
        ])
        chevron.alpha = 0.75
        
        addSubview(chainIcon)
        addSubview(label)
        addSubview(chevron)
        chevronSpacingConstraint = chevron.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 2)
        NSLayoutConstraint.activate([
            chainIcon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: walletAddressPadding),
            chevron.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -walletAddressPadding),
            label.topAnchor.constraint(equalTo: topAnchor, constant: walletAddressPadding),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -walletAddressPadding),
            
            chainIcon.centerYAnchor.constraint(equalTo: label.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: chainIcon.trailingAnchor, constant: 6),
            chevron.bottomAnchor.constraint(equalTo: label.firstBaselineAnchor),
            chevronSpacingConstraint,
        ])
    }
    
    func update(currentNft: ApiNft?) {
        let account = AccountStore.account ?? DUMMY_ACCOUNT
        let isMultichain = account.isMultichain
        walletChainIconWidthConstraint.constant = isMultichain ? 26 : 16
        chainIcon.image = isMultichain ? .airBundle("MultichainIcon") : ApiChain.chainForAddress(account.firstAddress).image
        let gradientColor = currentNft?.gradientColor(in: label.bounds) ?? .white
        if isMultichain {
            label.text = lang("Multichain")
            label.font = .compact(ofSize: 17)
            label.textColor = gradientColor
            
        } else {
            label.attributedText = formatAddressAttributed(
                account.firstAddress ?? "",
                startEnd: true,
                primaryFont: .compact(ofSize: 17),
                primaryColor: gradientColor,
                secondaryColor: nil
            )
        }
        let tintColor = currentNft?.gradientColors().endColor ?? .white
        chevron.tintColor = tintColor
        chevron.image = .airBundle(isMultichain ? "ChevronDown10" : "HomeCopy")
        chevron.transform = isMultichain ? .identity : .init(scaleX: 0.9, y: 0.9).translatedBy(x: 0, y: -1)
        chevronSpacingConstraint.constant = isMultichain ? 2 : 6
        chevron.clipsToBounds = false
        
        chevron.contentMode = .center
    }
}
