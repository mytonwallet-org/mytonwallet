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

let headerHeight: CGFloat = 360

public class ReceiveVC: WViewController {
    
    private let selectedChain: ApiChain?
    private let customTitle: String?
    
    private var segmentedController: WSegmentedController!
    private var hostingController: UIHostingController<ReceiveHeaderView>!
    private var previousNavigationBarStyle: UIUserInterfaceStyle = .unspecified
    
    @AccountContext private var account: MAccount

    public init(accountContext: AccountContext, chain: ApiChain? = nil, title: String? = nil) {
        self._account = accountContext
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
    
    private func setupViews() {
        let isMultichain = account.isMultichain
        
        segmentedController = WSegmentedController(
            items: makeChainItems(),
            defaultItemId: selectedChain?.rawValue,
            barHeight: 0,
            goUnderNavBar: true,
            animationSpeed: .slow,
            primaryTextColor: .white,
            secondaryTextColor: .white,
            capsuleFillColor: .white.withAlphaComponent(0.16),
            style: .colorHeader
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
        segmentedController.segmentedControl.isHidden = !isMultichain
        segmentedController.scrollView.isScrollEnabled = isMultichain

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
        setNavigationControlsAppearance()
        
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
        if isMultichain {
            segmentedController.segmentedControl?.embed(in: navigationItem)
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
    
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        previousNavigationBarStyle = navigationController?.navigationBar.overrideUserInterfaceStyle ?? .unspecified
        navigationController?.navigationBar.overrideUserInterfaceStyle = .dark
    }
    
    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.navigationBar.overrideUserInterfaceStyle = .unspecified
        navigationController?.navigationBar.overrideUserInterfaceStyle = previousNavigationBarStyle
    }
    
    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        keepUserInterfaceStyleForChildPages()
    }
    
    /// Overrides user interface style to dark to turn off whitish tint for navigation controls (segmented tabs + close button)
    private func setNavigationControlsAppearance() {
        segmentedController.overrideUserInterfaceStyle = .dark
        keepUserInterfaceStyleForChildPages()
    }
    
    /// Restores system-wide user interface style overridden in `setNavigationControlsAppearance `
    private func keepUserInterfaceStyleForChildPages() {
        segmentedController.model.items.forEach {
             $0.viewController.overrideUserInterfaceStyle = traitCollection.userInterfaceStyle
        }
    }

    private func makeChainItems() -> [SegmentedControlItem] {
        _account.orderedChains.map { (chain, _) in
            SegmentedControlItem(
                id: chain.rawValue,
                title: chain.title,
                viewController: ReceiveTableVC(account: _account, chain: chain, customTitle: chain.title),
            )
        }
    }
    
    private func updateTheme() {
        view.backgroundColor = .air.sheetBackground
    }
    
    public override func scrollToTop(animated: Bool) {
        segmentedController?.scrollToTop(animated: animated)
    }
            
    private func makeHeader() -> ReceiveHeaderView {
        ReceiveHeaderView(viewModel: segmentedController.model, accountContext: _account)
    }
}

#if DEBUG
@available(iOS 26, *)
#Preview {
    previewSheet(ReceiveVC(accountContext: AccountContext(source: .current)))
}
#endif
