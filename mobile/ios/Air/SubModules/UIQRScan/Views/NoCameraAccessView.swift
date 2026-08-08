//
//  NoCameraAccessView.swift
//  UIQRScan
//
//  Created by Sina on 5/13/23.
//

import UIKit
import UIComponents
import WalletContext

public class NoCameraAccessView: UIView {
    
    public init() {
        super.init(frame: CGRect.zero)
        setupView()
    }
    
    override public init(frame: CGRect) {
        fatalError()
    }
    
    required public init?(coder: NSCoder) {
        fatalError()
    }
    
    private func setupView() {
        translatesAutoresizingMaskIntoConstraints = false

        // bottom actions view
        let bottomActionsView = BottomActionsView(primaryAction: BottomAction(title: lang("Open Settings"), onPress: {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        }))
        addSubview(bottomActionsView)
        NSLayoutConstraint.activate([
            bottomActionsView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -58),
            bottomActionsView.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 48),
            bottomActionsView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -48),
        ])

        // top view
        let topView = UIView()
        topView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(topView)
        NSLayoutConstraint.activate([
            topView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            topView.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),
            topView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor),
            topView.bottomAnchor.constraint(equalTo: bottomActionsView.topAnchor)
        ])

        // header, center of top view
        let headerView = HeaderView(title: lang("No Camera Access"),
                                    description: lang("Permission denied. Please grant camera permission to use the QR code scanner."))
        headerView.lblTitle.textColor = .white
        headerView.lblDescription.textColor = .white
        if Language.current == .ru {
            headerView.lblTitle.isHidden = true
        }
        topView.addSubview(headerView)
        NSLayoutConstraint.activate([
            headerView.leadingAnchor.constraint(equalTo: topView.leadingAnchor, constant: 32),
            headerView.trailingAnchor.constraint(equalTo: topView.trailingAnchor, constant: -32),
            headerView.centerYAnchor.constraint(equalTo: topView.centerYAnchor)
        ])
    }
    
}
