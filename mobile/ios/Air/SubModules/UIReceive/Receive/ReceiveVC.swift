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
    
    public let onlyChain: ApiChain?
    public let showBuyOptions: Bool
    public let customTitle: String?
    
    private var segmentedController: WSegmentedController!
    private var hostingController: UIHostingController<ReceiveHeaderView>!
    private let headerViewModel = ReceiveHeaderViewModel()

    public init(chain: ApiChain? = nil, showBuyOptions: Bool = true, title: String? = nil) {
        var onlyChain = chain
        if let account = AccountStore.account, account.byChain.count <= 1, let first = account.addressByChain.first {
            onlyChain = ApiChain(rawValue: first.key)
        }
        self.onlyChain = onlyChain
        self.showBuyOptions = showBuyOptions
        self.customTitle = title
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
      
        let twoTabs = onlyChain == nil &&  ApiChain.tron.activeWalletAddressOnChain != nil
        let tonVC = ReceiveTableVC(chain: onlyChain ?? .ton, showBuyOptions: showBuyOptions, customTitle: ApiChain.ton.symbol)
        let tronVC = ReceiveTableVC(chain: onlyChain ?? (twoTabs ? .tron : .ton), showBuyOptions: showBuyOptions, customTitle: ApiChain.tron.symbol)

        addChild(tonVC)
        addChild(tronVC)
        
        let items: [SegmentedControlItem] = [
            SegmentedControlItem(
                id: tonVC.chain.rawValue,
                title: tonVC.chain.symbol,
                viewController: tonVC
            ),
            SegmentedControlItem(
                id: tronVC.chain.rawValue,
                title: tronVC.chain.symbol,
                viewController: tronVC
            ),
        ]
        
        segmentedController = WSegmentedController(
            items: items,
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
        segmentedController.segmentedControl.isHidden = !twoTabs
        segmentedController.scrollView.isScrollEnabled = twoTabs

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
        if twoTabs {
            let segmentedControl = segmentedController.segmentedControl!
            segmentedControl.removeFromSuperview()
            navigationItem.titleView = segmentedControl
            segmentedControl.widthAnchor.constraint(equalToConstant: 200).isActive = true
        } else {
            segmentedController.segmentedControl.removeFromSuperview()
            navigationItem.title = customTitle ?? lang("Add Crypto")
        }

        updateTheme()
    }
    
    public override func updateTheme() {
        view.backgroundColor = WTheme.sheetBackground
        segmentedController.updateTheme()
    }
    
    public override func scrollToTop(animated: Bool) {
        segmentedController?.scrollToTop(animated: animated)
    }
    
    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateTheme()
    }
    
    public func segmentedController(scrollOffsetChangedTo progress: CGFloat) {
        self.headerViewModel.progress = progress
    }
    
    func makeHeader() -> ReceiveHeaderView {
        ReceiveHeaderView(chain1: onlyChain ?? .ton, chain2: .tron, viewModel: headerViewModel)
    }
}


// MARK: - Header

@Perceptible
final class ReceiveHeaderViewModel {
    var progress: CGFloat = 0
}

struct ReceiveHeaderView: View {
    
    let chain1: ApiChain
    let chain2: ApiChain
    var viewModel: ReceiveHeaderViewModel
        
    var body: some View {
        WithPerceptionTracking {
            ZStack {
                ZStack {
                    Color(WTheme.background)
                    Image(chain1 == .ton ? "Receive.Background.Ton" : "Receive.Background.Tron", bundle: AirBundle)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .opacity(1 - viewModel.progress)
                    Image(chain2 == .ton ? "Receive.Background.Ton" : "Receive.Background.Tron", bundle: AirBundle)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .opacity(viewModel.progress)
                }
                
                ZStack {
                    ReceiveHeaderItemView(chain: chain1, direction: -1, progress: viewModel.progress)
                    ReceiveHeaderItemView(chain: chain2, direction: 1, progress: 1 - viewModel.progress)
                }
                .padding(.top, 48)
            }
        }
    }
}

private func inter(_ from: CGFloat, _ to: CGFloat, _ progress: CGFloat) -> CGFloat {
    from * (1 - progress) + to * progress
}

struct ReceiveHeaderItemView: View {
    
    let chain: ApiChain
    let direction: CGFloat
    var progress: CGFloat
    
    var body: some View {
        WithPerceptionTracking {
            let progress1 = 1 - progress
            let progress2 = progress
            
            ZStack {
                Image(chain == .ton ? "Receive.Ornament.Ton" : "Receive.Ornament.Tron", bundle: AirBundle)
                    .blendMode(.softLight)
                    .opacity(inter(0.25, 1, progress1))
                
                _QRCodeView(chain: chain, opacity: inter(0.25, 1, progress1), onTap: {})
                    .frame(width: 220, height: 220)
                    .clipShape(.rect(cornerRadius: 32))
            }
            .scaleEffect(min(1.05, inter(0.5, 1, progress1)))
            .offset(x: progress2 * 320 * direction)
            .rotation3DEffect(.degrees(-10) * progress2 * direction, axis: (0, 1, 0))
        }
    }
}


struct _QRCodeView: UIViewRepresentable {
        
    let chain: ApiChain
    var opacity: CGFloat
    let onTap: () -> ()
    
    init(chain: ApiChain, opacity: CGFloat, onTap: @escaping () -> Void) {
        self.chain = chain
        self.opacity = opacity
        self.onTap = onTap
    }
    
    final class Coordinator: QRCodeContainerViewDelegate {
        var onTap: () -> ()
        init(onTap: @escaping () -> Void) {
            self.onTap = onTap
        }
        func qrCodePressed() {
            onTap()
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap)
    }
    
    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = .white
        let url = chain.activeWalletWalletInvoiceUrl ?? ApiChain.ton.activeWalletWalletInvoiceUrl ?? "Error"
        let view = QRCodeContainerView(url: url, image: chain.image, size: 200, centerImageSize: 40, delegate: context.coordinator)
        container.addSubview(view)
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: 220),
            container.heightAnchor.constraint(equalToConstant: 220),
            view.widthAnchor.constraint(equalToConstant: 200),
            view.heightAnchor.constraint(equalToConstant: 200),
            view.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            view.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        return container
    }
    
    public func updateUIView(_ uiView: UIView, context: Context) {
        uiView.alpha = self.opacity
    }
}


// MARK: - Table

class ReceiveTableVC: WViewController, WSegmentedControllerContent {
    
    let chain: ApiChain
    
    private let showBuyOptions: Bool
    public init(chain: ApiChain, showBuyOptions: Bool, customTitle: String? = nil) {
        self.chain = chain
        self.showBuyOptions = showBuyOptions
        super.init(nibName: nil, bundle: nil)
        title = customTitle ?? lang("Add Crypto")
    }
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Load and SetupView Functions
    public override func loadView() {
        super.loadView()
        setupViews()
    }

    private func setupViews() {
        view.backgroundColor = .clear
        let tableView = UITableView()
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.separatorStyle = .none
        tableView.contentInset.top = headerHeight
        tableView.contentInset.bottom = 16
        tableView.contentInsetAdjustmentBehavior = .never
        tableView.bounces = false // disabling scrolling messes with dismiss gesture so we just disable overscroll
        tableView.delaysContentTouches = false
        tableView.backgroundColor = .clear
        tableView.register(SectionHeaderCell.self, forCellReuseIdentifier: "Header")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Footer")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Address")
        tableView.register(BuyCryptoCell.self, forCellReuseIdentifier: "BuyCrypto")
        tableView.backgroundColor = .clear
        view.insertSubview(tableView, at: 0)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leftAnchor.constraint(equalTo: view.leftAnchor),
            tableView.rightAnchor.constraint(equalTo: view.rightAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        updateTheme()
    }
    
    public override func updateTheme() {
    }
    
    // segmented control support
    public var onScroll: ((CGFloat) -> Void)?
    public var onScrollStart: (() -> Void)?
    public var onScrollEnd: (() -> Void)?
    public var scrollingView: UIScrollView? { view.subviews.first as? UIScrollView }
}

extension ReceiveTableVC: UITableViewDelegate, UITableViewDataSource {
    
    public func numberOfSections(in tableView: UITableView) -> Int {
        showBuyOptions && !ConfigStore.shared.shouldRestrictSwapsAndOnRamp ? 2 : 1
    }

    var shouldShowDepositLink: Bool {
        chain == .ton
    }
    
    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0:
            return 2
        case 1:
            var count = 2
            if shouldShowDepositLink {
                count += 1
            }
            if ConfigStore.shared.shouldRestrictSwapsAndOnRamp {
                count -= 1
            }
            return count
        default:
            return 0
        }
    }
    
    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch indexPath.section {
        case 0:
            // top header
            switch indexPath.row {
            case 0:
                let cell = tableView.dequeueReusableCell(withIdentifier: "Header", for: indexPath) as! SectionHeaderCell
                let title = lang("Your %blockchain% Address", arg1: chain.symbol)
                cell.configure(title: title.uppercased(), spacing: 0)
                return cell
                
            case 1:
                // top address view
                let cell = tableView.dequeueReusableCell(withIdentifier: "Address", for: indexPath)
                
                let address = chain.activeWalletAddressOnChain!
                
                cell.contentConfiguration = UIHostingConfiguration { [weak self] in
                    let copy = Text(
                        Image("HomeCopy", bundle: AirBundle)
                    )
                        .baselineOffset(-3)
                        .foregroundColor(Color(WTheme.secondaryLabel))
                    let addressText = Text(address: address)
                    let text = Text("\(addressText) \(copy)")
                        .font(.system(size: 17, weight: .regular))
                        .lineSpacing(2)
                        .multilineTextAlignment(.leading)
                    
                    Button(action: {
                        self?.showToast(animationName: "Copy", message: lang("Address was copied!"))
                        Haptics.play(.lightTap)
                        UIPasteboard.general.string = address
                    }) {
                        text
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                    .padding(.top, 1)
                }
                .background(content: {
                    Color(WTheme.groupedItem)
                        .clipShape(.rect(cornerRadius: S.addressSectionCornerRadius))
                        .padding(.horizontal, 16)
                })
                return cell
                
            default:
                fatalError()
            }
            
        case 1:
            // buy crypto items
            let cell = tableView.dequeueReusableCell(withIdentifier: "BuyCrypto", for: indexPath) as! BuyCryptoCell
            var row = indexPath.row
            if ConfigStore.shared.shouldRestrictSwapsAndOnRamp {
                row += 1
            }
            switch row {
            case 0:
                cell.configure(position: .top,
                               image: UIImage(named: "CardIcon", in: AirBundle, compatibleWith: nil)!,
                               title: lang("Buy with Card")) { [weak self] in
                    AppActions.showBuyWithCard(chain: self?.chain, push: true)
                }
            case 1:
                cell.configure(position: shouldShowDepositLink ? .middle : .bottom,
                               image: UIImage(named: "CryptoIcon", in: AirBundle, compatibleWith: nil)!,
                               title: lang("Buy with Crypto")) {
                    AppActions.showSwap(defaultSellingToken: TRON_USDT_SLUG, defaultBuyingToken: nil, defaultSellingAmount: nil, push: true)
                }
            case 2:
                cell.configure(position: .bottom,
                               image: UIImage(named: "AssetsAndActivityIcon", in: AirBundle, compatibleWith: nil)!,
                               title: lang("Create Deposit Link")) {
                    self.navigationController?.pushViewController(DepositLinkVC(), animated: true)
                }
            default:
                fatalError()
            }
            return cell
        default:
            fatalError()
        }
    }
    
    public func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        12
    }
    
    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        section == 0 ? " " : ""
    }
}
