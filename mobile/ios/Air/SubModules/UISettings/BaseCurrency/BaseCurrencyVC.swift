//
//  BaseCurrencyVC.swift
//  UISettings
//
//  Created by Sina on 7/5/24.
//

import Foundation
import UIKit
import UIComponents
import WalletCore
import WalletContext

fileprivate let baseCurrencies: [MBaseCurrency] = [
    .USD, .EUR, .RUB, .CNY, .BTC, .TON
]

public class BaseCurrencyVC: WViewController {
    
    private let isModal: Bool
    public init(isModal: Bool) {
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
    
    private var tableView: UITableView!
    private func setupViews() {
        title = lang("Base Currency")
        
        tableView = UITableView()
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(SectionHeaderCell.self, forCellReuseIdentifier: "Header")
        tableView.register(TitleSubtitleSelectableCell.self, forCellReuseIdentifier: "CurrencyCell")
        tableView.separatorStyle = .none
        tableView.delaysContentTouches = false
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leftAnchor.constraint(equalTo: view.leftAnchor),
            tableView.rightAnchor.constraint(equalTo: view.rightAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
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

extension BaseCurrencyVC: UITableViewDelegate, UITableViewDataSource {
    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 1 + baseCurrencies.count
    }
    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.row == 0 {
            let cell = tableView.dequeueReusableCell(withIdentifier: "Header", for: indexPath) as! SectionHeaderCell
            cell.configure(title: lang("Main Currency").uppercased())
            return cell
        }
        let baseCurrency = baseCurrencies[indexPath.row - 1]
        let cell = tableView.dequeueReusableCell(withIdentifier: "CurrencyCell", for: indexPath) as! TitleSubtitleSelectableCell
        cell.configure(title: baseCurrency.symbol,
                       subtitle: baseCurrency.name,
                       isSelected: TokenStore.baseCurrency.rawValue == baseCurrency.rawValue,
                       isFirst: indexPath.row == 1,
                       isLast: indexPath.row == baseCurrencies.count,
                       isInModal: isModal,
                       onSelect: { [weak self] in
            guard let self else {return}
            Task {
                do {
                    try await TokenStore.setBaseCurrency(currency: baseCurrency)
                } catch {
                }
            }
            navigationController?.popViewController(animated: true)
        })
        return cell
    }
}
