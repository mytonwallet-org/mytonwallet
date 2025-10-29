//
//  ChooseWalletVC.swift
//  UIComponents
//
//  Created by Sina on 8/31/24.
//

import UIKit
import WalletCore
import WalletContext

public class ChooseWalletVC: WViewController {
    
    private let accounts = AccountStore.allAccounts.filter { !$0.isView }

    private let hint: String
    private var selectedAccountId: String
    private let isModal: Bool
    private let onSelect: (MAccount) -> Void
    public init(hint: String, selectedAccountId: String, isModal: Bool = false, onSelect: @escaping (MAccount) -> Void) {
        self.hint = hint
        self.selectedAccountId = selectedAccountId
        self.isModal = isModal
        self.onSelect = onSelect
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
    
    private var tableView: UITableView!
    private func setupViews() {
        addNavigationBar(
            title: lang("Choose Wallet"),
            subtitle: nil,
            closeIcon: true,
        )
        
        tableView = UITableView()
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(SectionHeaderCell.self, forCellReuseIdentifier: "Header")
        tableView.register(ImageTitleSubtitleSelectableCell.self, forCellReuseIdentifier: "Account")
        tableView.separatorStyle = .none
        tableView.delaysContentTouches = false
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: navigationBarAnchor),
            tableView.leftAnchor.constraint(equalTo: view.leftAnchor),
            tableView.rightAnchor.constraint(equalTo: view.rightAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        updateTheme()
    }
    
    public override func updateTheme() {
        view.backgroundColor = isModal ? WTheme.sheetBackground : WTheme.groupedBackground
        tableView.backgroundColor = view.backgroundColor
    }

    public override func scrollToTop(animated: Bool) {
        tableView?.setContentOffset(CGPoint(x: 0, y: -tableView.adjustedContentInset.top), animated: animated)
    }
    
}

extension ChooseWalletVC: UITableViewDelegate, UITableViewDataSource {
    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 1 + accounts.count
    }
    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.row == 0 {
            let cell = tableView.dequeueReusableCell(withIdentifier: "Header", for: indexPath) as! SectionHeaderCell
            cell.configure(title: hint)
            return cell
        }
        let account = accounts[indexPath.row - 1]
        let cell = tableView.dequeueReusableCell(withIdentifier: "Account", for: indexPath) as! ImageTitleSubtitleSelectableCell
        cell.configure(title: account.displayName,
                       subtitle: formatStartEndAddress(account.tonAddress ?? ""),
                       isSelected: account.id == selectedAccountId,
                       isFirst: indexPath.row == 1,
                       isLast: indexPath.row == accounts.count,
                       isInModal: isModal) { [weak self] in
            guard let self else { return }
            onSelect(account)
            if navigationController?.viewControllers.count ?? 0 > 1 {
                navigationController?.popViewController(animated: true)
            } else {
                dismiss(animated: true)
            }
        }
        cell.img.config(with: account, showIcon: true)
        return cell
    }
}
