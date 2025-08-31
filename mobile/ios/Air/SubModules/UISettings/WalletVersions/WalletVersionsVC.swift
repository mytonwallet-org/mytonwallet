//
//  WalletVersionsVC.swift
//  UISettings
//
//  Created by Sina on 7/14/24.
//

import Foundation
import UIKit
import UIComponents
import WalletCore
import WalletContext

fileprivate let rightArrowImage = UIImage(named: "RightArrowIcon", in: AirBundle, compatibleWith: nil)!.withRenderingMode(.alwaysTemplate)

public class WalletVersionsVC: WViewController {
    
    private let isModal: Bool
    public init(isModal: Bool = false) {
        self.isModal = isModal
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Load and SetupView Functions
    public override func loadView() {
        super.loadView()
        setupViews()
    }
    
    public override var hideNavigationBar: Bool {
        true
    }
    
    private var tableView: UITableView!
    private var footerLabel: UILabel!
    private var walletVersionsData: MWalletVersionsData? = nil
    private func setupViews() {
        title = lang("TON Wallet Versions")

        walletVersionsData = AccountStore.walletVersionsData

        tableView = UITableView()
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(SectionHeaderCell.self, forCellReuseIdentifier: "Header")
        tableView.register(TitleSubtitleSelectableCell.self, forCellReuseIdentifier: "VersionCell")
        tableView.register(WalletVersionsHintCell.self, forCellReuseIdentifier: "Hint")
        tableView.separatorStyle = .none
        tableView.delaysContentTouches = false
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leftAnchor.constraint(equalTo: view.leftAnchor),
            tableView.rightAnchor.constraint(equalTo: view.rightAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        addNavigationBar(navHeight: 40,
                                       topOffset: -5,
                                       title: title,
                                       addBackButton: { [weak self] in
            guard let self else {return}
            navigationController?.popViewController(animated: true)
        })
        tableView.contentInset.top = navigationBarHeight
        tableView.verticalScrollIndicatorInsets.top = navigationBarHeight
        tableView.contentOffset.y = -navigationBarHeight

        updateTheme()
    }
    
    public override func updateTheme() {
        view.backgroundColor = isModal ? WTheme.groupedBackground : WTheme.groupedBackground
        tableView.backgroundColor = view.backgroundColor
    }

    public override func scrollToTop(animated: Bool) {
        tableView?.setContentOffset(CGPoint(x: 0, y: -tableView.adjustedContentInset.top), animated: animated)
    }
}

extension WalletVersionsVC: UITableViewDelegate, UITableViewDataSource {
    public func numberOfSections(in tableView: UITableView) -> Int {
        return 3
    }
    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0:
            return 2
        case 1:
            return 1 + (walletVersionsData?.versions.count ?? 0)
        case 2:
            return 1
        default:
            return 0
        }
    }
    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch indexPath.section {
        case 0:
            if indexPath.row == 0 {
                let cell = tableView.dequeueReusableCell(withIdentifier: "Header", for: indexPath) as! SectionHeaderCell
                cell.configure(title: lang("Current Wallet Version").uppercased())
                return cell
            }
            let cell = tableView.dequeueReusableCell(withIdentifier: "VersionCell", for: indexPath) as! TitleSubtitleSelectableCell
            cell.configure(title: walletVersionsData?.currentVersion ?? "",
                           subtitle: formatStartEndAddress(AccountStore.account?.tonAddress ?? ""),
                           isSelected: true,
                           isFirst: true,
                           isLast: true,
                           isInModal: false,
                           subtitleColor: WTheme.secondaryLabel,
                           onSelect: { [weak self] in
                self?.navigationController?.popViewController(animated: true)
            })
            return cell
        case 1:
            if indexPath.row == 0 {
                let cell = tableView.dequeueReusableCell(withIdentifier: "Header", for: indexPath) as! SectionHeaderCell
                cell.configure(title: lang("Tokens on Other Versions").uppercased(), spacing: 8)
                return cell
            }
            let cell = tableView.dequeueReusableCell(withIdentifier: "VersionCell", for: indexPath) as! TitleSubtitleSelectableCell
            let version = walletVersionsData!.versions[indexPath.row - 1]
            let value: String
            if let balance = MTokenBalance(tokenSlug: "toncoin", balance: version.balance, isStaking: false).toBaseCurrency {
                value = formatAmountText(amount: balance, currency: TokenStore.baseCurrency?.sign, decimalsCount: TokenStore.baseCurrency?.decimalsCount)
            } else {
                value = ""
            }
            cell.configure(title: version.version,
                           subtitle: formatStartEndAddress(version.address),
                           isSelected: false,
                           isFirst: indexPath.row == 1,
                           isLast: indexPath.row == walletVersionsData?.versions.count,
                           isInModal: false,
                           value: value,
                           rightIcon: rightArrowImage,
                           subtitleColor: WTheme.secondaryLabel,
                           onSelect: { [weak self] in
                if let self, let accountId = AccountStore.accountId, let version = ApiTonWalletVersion(rawValue: version.version) {
                    Task { @MainActor in
                        do {
                            _ = try await AccountStore.importNewWalletVersion(accountId: accountId, version: version)
                            self.navigationController?.popViewController(animated: false)
                        } catch {
                            self.showAlert(error: error)
                        }
                    }
                }
            })
            return cell
        case 2:
            return tableView.dequeueReusableCell(withIdentifier: "Hint", for: indexPath)
        default:
            fatalError()
        }
    }
    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        navigationBar?.showSeparator = scrollView.contentOffset.y + scrollView.contentInset.top + view.safeAreaInsets.top > 0
    }
}
