import SwiftUI
import UIKit
import UIComponents
import WalletContext
import WalletCore
import Perception

final class ReceiveTableVC: WViewController, WSegmentedControllerContent, UITableViewDelegate, UITableViewDataSource {
    
    @AccountViewModel private var account: MAccount
    let chain: ApiChain
    
    public init(account: AccountViewModel, chain: ApiChain, customTitle: String? = nil) {
        self._account = account
        self.chain = chain
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

    public func numberOfSections(in tableView: UITableView) -> Int {
        !ConfigStore.shared.shouldRestrictSwapsAndOnRamp ? 2 : 1
    }

    var shouldShowDepositLink: Bool {
        chain.formatTransferUrl != nil
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
                let title = lang("Your %blockchain% Address", arg1: chain.title)
                cell.configure(title: title.uppercased(), spacing: 0)
                return cell
                
            case 1:
                // top address view
                let cell = tableView.dequeueReusableCell(withIdentifier: "Address", for: indexPath)
                
                let address = account.addressByChain[chain.rawValue]!
                
                cell.contentConfiguration = UIHostingConfiguration {
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
                        AppActions.showToast(animationName: "Copy", message: lang("Address was copied!"))
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
