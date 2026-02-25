//
//  ReceiveVC.swift
//  UIHome
//
//  Created by Sina on 4/22/23.
//

import SwiftUI
import UIKit
import UIComponents
import WalletContext
import WalletCore
import Perception

let headerHeight: CGFloat = 340

public class ReceiveVC: WViewController, WSegmentedController.Delegate {
    
    private let selectedChain: ApiChain?
    private let customTitle: String?
    
    private var segmentedController: WSegmentedController!
    private var hostingController: UIHostingController<ReceiveHeaderView>!
    
    @AccountContext(source: .current) private var account: MAccount

    public init(chain: ApiChain? = nil, title: String? = nil) {
        self.customTitle = title
        self.selectedChain = chain
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func loadView() {
        super.loadView()
        setupViews()
    }
    
    func setupViews() {
        view.backgroundColor = WTheme.sheetBackground
      
        segmentedController = WSegmentedController(
            items: makeChainItems(),
            defaultItemId: selectedChain?.rawValue,
            barHeight: 0,
            goUnderNavBar: true,
            animationSpeed: .slow,
            primaryTextColor: .white,
            secondaryTextColor: .white.withAlphaComponent(0.75),
            capsuleFillColor: .white.withAlphaComponent(0.15),
            delegate: self
        )
        
        segmentedController.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(segmentedController)
        NSLayoutConstraint.activate([
            segmentedController.topAnchor.constraint(equalTo: view.topAnchor),
            segmentedController.leftAnchor.constraint(equalTo: view.leftAnchor),
            segmentedController.rightAnchor.constraint(equalTo: view.rightAnchor),
            segmentedController.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        segmentedController.backgroundColor = .clear
        segmentedController.blurView.isHidden = true
        segmentedController.separator.isHidden = true
        segmentedController.segmentedControl.isHidden = !account.isMultichain
        segmentedController.scrollView.isScrollEnabled = account.isMultichain

        self.hostingController = addHostingController(makeHeader()) { hv in
            NSLayoutConstraint.activate([
                hv.topAnchor.constraint(equalTo: self.view.topAnchor),
                hv.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
                hv.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
                hv.heightAnchor.constraint(equalToConstant: headerHeight)
            ])
        }
        hostingController.disableSafeArea()
        hostingController.view.clipsToBounds = true
        
        view.bringSubviewToFront(segmentedController)
        
        configureNavigationItemWithTransparentBackground()
        
        if #available(iOS 26, *) {
            addCloseNavigationItemIfNeeded()
        } else {
            let image = UIImage(systemName: "xmark")
            let item = UIBarButtonItem(image: image, primaryAction: UIAction { _ in
                topViewController()?.dismiss(animated: true)
            })
            item.tintColor = .white.withAlphaComponent(0.75)
            navigationItem.rightBarButtonItem = item
        }
        if account.isMultichain {
            let segmentedControl = segmentedController.segmentedControl!
            segmentedControl.removeFromSuperview()
            navigationItem.titleView = segmentedControl
            segmentedControl.widthAnchor.constraint(equalToConstant: 200).isActive = true
        } else {
            segmentedController.segmentedControl.removeFromSuperview()
            navigationItem.titleView = HostingView {
                NavigationHeader {
                    Text(customTitle ?? lang("Add Crypto"))
                        .foregroundStyle(.white)
                }
            }
        }

        updateTheme()
    }
    
    func makeChainItems() -> [SegmentedControlItem] {
        account.orderedChains.map { (chain, _) in
            SegmentedControlItem(
                id: chain.rawValue,
                title: chain.title,
                viewController: ReceiveTableVC(account: _account, chain: chain, customTitle: chain.title),
            )
        }
    }
    
    public override func updateTheme() {
        view.backgroundColor = WTheme.sheetBackground
    }
    
    public override func scrollToTop(animated: Bool) {
        segmentedController?.scrollToTop(animated: animated)
    }
    
    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateTheme()
    }
    
    public func segmentedController(scrollOffsetChangedTo progress: CGFloat) {
    }
    
    func makeHeader() -> ReceiveHeaderView {
        ReceiveHeaderView(viewModel: segmentedController.model, accountContext: _account)
    }
}

#if DEBUG
@available(iOS 26, *)
#Preview {
    previewSheet(ReceiveVC())
}
#endif
