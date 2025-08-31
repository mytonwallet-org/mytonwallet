//
//  LanguageVC.swift
//  UISettings
//
//  Created by Sina on 7/5/24.
//

import Foundation
import UIKit
import UIComponents
import WalletCore
import WalletContext
import SwiftUI

public class LanguageVC: WViewController {
    
    private let isModal: Bool
    public init(isModal: Bool = false) {
        self.isModal = isModal
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    let languages = Language.supportedLanguages
    
    // MARK: - Load and SetupView Functions
    public override func loadView() {
        super.loadView()
        setupViews()
    }
    
    private var tableView: UITableView!
    private func setupViews() {
        title = lang("Language")
        
        tableView = UITableView()
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(SectionHeaderCell.self, forCellReuseIdentifier: "Header")
        tableView.register(TitleSubtitleSelectableCell.self, forCellReuseIdentifier: "CurrencyCell")
        tableView.separatorStyle = .none
        tableView.delaysContentTouches = false
        
//        let headerLabel = HostingView(ignoreSafeArea: false) {
//            Text("Localization is a work in progress. For the best experience, please use English.")
//                .font13()
//                .padding(.top, 24)
//                .padding(.bottom, 8)
//                .padding(.horizontal, 32)
//                .multilineTextAlignment(.leading)
//                .frame(maxWidth: UIScreen.main.bounds.width - 32, alignment: .leading)
//                .foregroundStyle(Color.orange)
//        }
//        headerLabel.frame.size.height = 52
//        tableView.tableHeaderView = headerLabel
        
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

extension LanguageVC: UITableViewDelegate, UITableViewDataSource {
    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 1 + languages.count
    }
    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.row == 0 {
            let cell = tableView.dequeueReusableCell(withIdentifier: "Header", for: indexPath) as! SectionHeaderCell
            cell.configure(title: lang("Interface language").uppercased())
            return cell
        }
        let language = languages[indexPath.row - 1]
        let cell = tableView.dequeueReusableCell(withIdentifier: "CurrencyCell", for: indexPath) as! TitleSubtitleSelectableCell
        cell.configure(title: language.name,
                       subtitle: language.nativeName,
                       isSelected: LocalizationSupport.shared.langCode == language.langCode,
                       isFirst: indexPath.row == 1,
                       isLast: indexPath.row == languages.count,
                       isInModal: isModal,
                       onSelect: {
            LocalizationSupport.shared.setLanguageCode(language.langCode)
            // do we need this?
            UserDefaults.standard.set([language.id], forKey: "AppleLanguages")
            UserDefaults.standard.synchronize()
            WalletContextManager.delegate?.restartApp()
        })
        return cell
    }
}
