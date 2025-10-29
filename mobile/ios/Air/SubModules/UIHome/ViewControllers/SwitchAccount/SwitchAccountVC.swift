//
//  SwitchAccountVC.swift
//  UIHome
//
//  Created by Sina on 5/8/24.
//

import UIKit
import UIPasscode
import UIComponents
import WalletCore
import WalletContext

public class SwitchAccountVC: WViewController {
    
    var dismissCallback: (() -> ())?
    
    // MARK: - Initializer
    private let activeAccount: MAccount
    private let otherAccounts: [MAccount]
    
    var startingGestureRecognizer: UIGestureRecognizer?
    private var iconColor: UIColor
    
    private let blurView = BlurredMenuBackground()
    
    private var tableView: UITableView!
    private var feedbackGenerator: UIImpactFeedbackGenerator!
    private var switchedAccount: Bool = false
    
    private var calculatedHeight:  CGFloat {
        88.0 + // first section
        (otherAccounts.count > 0 ? 8.0 : 0.0) + // divider
        CGFloat(otherAccounts.count) * 44.0 // other accounts
    }
    
    public init(accounts: [MAccount], iconColor: UIColor) {
        self.activeAccount = AccountStore.account!
        self.otherAccounts = accounts.filter { $0.id != AccountStore.accountId }
        self.iconColor = iconColor
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Load and SetupView Functions
    public override func loadView() {
        super.loadView()
        view.backgroundColor = .clear
        setupViews()
    }
    
    private lazy var tabImageView: UIImageView = {
        let tabImageView = UIImageView()
        tabImageView.translatesAutoresizingMaskIntoConstraints = false
        tabImageView.image = UIImage(named: "tab_settings", in: AirBundle, compatibleWith: nil)?.withRenderingMode(.alwaysTemplate)
        tabImageView.tintColor = self.iconColor
        return tabImageView
    }()
    
    private lazy var tabLabel: UILabel = {
        let tabLabel = UILabel()
        tabLabel.translatesAutoresizingMaskIntoConstraints = false
        tabLabel.font = .systemFont(ofSize: 10, weight: .medium)
        tabLabel.text = lang("Settings")
        tabLabel.textColor = iconColor
        return tabLabel
    }()
    
    private lazy var tabBarIcon: UIView = {
        let v = UIView()
        v.accessibilityIdentifier = "tabBarIcon"
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = .clear
        v.isUserInteractionEnabled = false
        v.addSubview(tabImageView)
        v.addSubview(tabLabel)
        NSLayoutConstraint.activate([
            tabImageView.topAnchor.constraint(equalTo: v.topAnchor),
            tabImageView.centerXAnchor.constraint(equalTo: v.centerXAnchor, constant: 0.33),
            tabLabel.topAnchor.constraint(equalTo: tabImageView.bottomAnchor, constant: 0),
            tabLabel.centerXAnchor.constraint(equalTo: v.centerXAnchor),
            tabLabel.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -1.33),
        ])
        return v
    }()
    
    private func setupViews() {
        view.backgroundColor = .clear
        
        blurView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(blurView)
        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: view.topAnchor),
            blurView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            blurView.leftAnchor.constraint(equalTo: view.leftAnchor),
            blurView.rightAnchor.constraint(equalTo: view.rightAnchor)
        ])
        blurView.alpha = 0
        blurView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(backPressed)))
        
        tableView = UITableView()
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.separatorStyle = .none
        tableView.contentInset.bottom = 16
        tableView.layer.cornerRadius = 12
        tableView.bounces = false
        tableView.isScrollEnabled = false
        tableView.register(AccountCell.self, forCellReuseIdentifier: "Account")
        tableView.backgroundColor = .clear
        tableView.isOpaque = false
        tableView.backgroundView = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
        // preparing animation
        view.addSubview(tableView)
        let heightConstraint = tableView.heightAnchor.constraint(equalToConstant: calculatedHeight)
        heightConstraint.priority = .defaultHigh
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -68),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            tableView.widthAnchor.constraint(equalToConstant: 228),
            heightConstraint
        ])
        
        
        if let recognizer = startingGestureRecognizer {
            recognizer.addTarget(self, action: #selector(handleLongPressGesture(_:)))
        }
        
        view.addSubview(tabBarIcon)
        NSLayoutConstraint.activate([
            tabBarIcon.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            tabBarIcon.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.333),
            tabBarIcon.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: IOS_26_MODE_ENABLED ? -50 : 0),
        ])
        
        feedbackGenerator = UIImpactFeedbackGenerator(style: .rigid)
        feedbackGenerator.prepare()
        
        updateTheme()
    }
    
    public override func updateTheme() {
        
    }
    
    public override var prefersStatusBarHidden: Bool { true }
    
    @objc func backPressed() {
        dismiss(animated: false)
    }
    
    @objc private func handleLongPressGesture(_ recognizer: UILongPressGestureRecognizer) {
        let location = recognizer.location(in: tableView)
        
        switch recognizer.state {
        case .changed:
            if let indexPath = tableView.indexPathForRow(at: location),
               let cell = tableView.cellForRow(at: indexPath) {
                for it in tableView.visibleCells {
                    if it == cell, it.isHighlighted == false {
                        feedbackGenerator.impactOccurred(intensity: 0.60)
                    }
                    it.isHighlighted = it == cell
                }
            } else {
                if tableView.visibleCells.contains(where: { it in
                    it.isHighlighted
                }) {
                    feedbackGenerator.impactOccurred(intensity: 0.30)
                }
                
                unhighlightAllCells()
            }
            break
        case .ended:
            if let indexPath = tableView.indexPathForRow(at: location) {
                accountSelected(indexPath: indexPath)
                unhighlightAllCells()
            }
        default:
            break
        }
    }
    
    public override func viewWillAppear(_ animated: Bool) {
        if IOS_26_MODE_ENABLED {
            tableView.transform = .init(translationX: 0, y: calculatedHeight/2 - 30).scaledBy(x: 0.25, y: 0.25)
        } else {
            tableView.transform = .init(translationX: 60.0, y: calculatedHeight/2 - 30).scaledBy(x: 0.25, y: 0.25)
        }
        tableView.transform = .init(translationX: 60.0, y: calculatedHeight/2 - 30).scaledBy(x: 0.25, y: 0.25)
        //        tabBarIcon.transform = .identity.scaledBy(x: 0.9, y: 0.9) // matching real icon
        
        UIView.transition(with: self.view, duration: 0.2) { [self] in
            blurView.alpha = 1
        }
        UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.75, initialSpringVelocity: 0.2) { [self] in
            tableView.transform = .identity
            tabBarIcon.transform = .identity.translatedBy(x: 0, y: -5)
            tabImageView.tintColor = WTheme.tint
            tabLabel.textColor = WTheme.tint
        }
    }
    
    public override func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
        dismissCallback?()
        UIView.transition(with: self.view, duration: 0.2) { [self] in
            view.layer.backgroundColor = UIColor.black.withAlphaComponent(0.0).cgColor
        }
        let duration = flag ? 0.35 : 0.25
        UIView.transition(with: self.view, duration: duration) { [self] in
            blurView.alpha = 0
        }
        let targetColor = switchedAccount ? WTheme.secondaryLabel : iconColor
        UIView.animate(withDuration: duration, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.2) { [self] in
            if flag {
                tableView.transform = .init(translationX: 60.0, y: calculatedHeight/2 - 30).scaledBy(x: 0.25, y: 0.25)
            }
            tabBarIcon.transform = .identity
            tableView.alpha = 0
            tabImageView.tintColor = targetColor
            tabLabel.textColor = targetColor
        }
        UIView.animate(withDuration: 0.1, delay: duration - 0.1, options: []) {
            self.tabBarIcon.alpha = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            self.presentingViewController?.dismiss(animated: false, completion: completion)
        }
    }
    
    private func unhighlightAllCells() {
        for cell in tableView.visibleCells {
            cell.isHighlighted = false
        }
    }
    
    private func switchAccount(to account: MAccount) {
        switchedAccount = true
        Task {
            do {
                _ = try await AccountStore.activateAccount(accountId: account.id)
                self.dismiss(animated: false)
            } catch {
                fatalError("failed to activate account: \(account.id)")
            }
        }
    }
    
    public func accountSelected(indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch indexPath.section {
        case 0:
            if indexPath.row == 0 {
                addAccountSelected()
            } else {
                switchAccount(to: activeAccount)
            }
        case 2:
            switchAccount(to: otherAccounts[indexPath.row])
        default:
            break
        }
    }
    
    private func addAccountSelected() {
        dismiss(animated: false) {
            AppActions.showAddWallet(showCreateWallet: true, showSwitchToOtherVersion: true)
        }
    }
}

extension SwitchAccountVC: UITableViewDelegate, UITableViewDataSource {
    public func numberOfSections(in tableView: UITableView) -> Int {
        otherAccounts.count > 0 ? 3 : 1
    }

    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0:
            return 2
        case 1:
            return 1
        default:
            return otherAccounts.count
        }
    }
    
    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch indexPath.section {
        case 0:
            let cell = tableView.dequeueReusableCell(withIdentifier: "Account", for: indexPath) as! AccountCell
            cell.configure(account: indexPath.row == 1 ? activeAccount : nil, hideSeparator: indexPath.row == 1) { [weak self] in
                self?.accountSelected(indexPath: indexPath)
            }
            cell.backgroundColor = .clear
            return cell
        case 2:
            let cell = tableView.dequeueReusableCell(withIdentifier: "Account", for: indexPath) as! AccountCell
            cell.configure(account: otherAccounts[indexPath.row], hideSeparator: indexPath.row == otherAccounts.count - 1) { [weak self] in
                self?.accountSelected(indexPath: indexPath)
            }
            cell.backgroundColor = .clear
            return cell
        default:
            let cell = UITableViewCell()
            cell.selectionStyle = .none
            cell.contentView.backgroundColor = WTheme.backgroundReverse.withAlphaComponent(0.1)
            return cell
        }
    }
    
    public func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return indexPath.section == 1 ? 8 : 44
    }
}
