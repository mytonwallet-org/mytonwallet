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
import SwiftUI

private let menuCornerRadius: CGFloat = IOS_26_MODE_ENABLED ? 26 : 12
private let switchAccountDividerHeight: CGFloat = 8
private let accountRowContentHeight: CGFloat = 40
private let accountRowVerticalMargin: CGFloat = 10
private let accountRowHeight: CGFloat = accountRowContentHeight + accountRowVerticalMargin * 2
private let actionRowIconSize: CGFloat = 30
private let actionRowVerticalPadding: CGFloat = IOS_26_MODE_ENABLED ? 11 : 7
private let actionRowHeight: CGFloat = actionRowIconSize + actionRowVerticalPadding * 2
private let switchAccountMaxAccountsShown: Int = 7

public class SwitchAccountVC: WViewController {
    
    // MARK: - Diffable Data Source Types
    
    private enum Section: Hashable {
        case activeSection
        case divider
        case otherAccounts
    }
    
    private enum Item: Hashable {
        case addAccount
        case showAllWallets
        case activeAccount(MAccount)
        case divider
        case otherAccount(MAccount)
    }
    
    // MARK: - Properties
    
    var dismissCallback: (() -> Void)?
    var startingGestureRecognizer: UIGestureRecognizer?
    
    private let activeAccount: MAccount
    private let otherAccounts: [MAccount]
    private var iconColor: UIColor
    private let blurView = BlurredMenuBackground()
    private var collectionView: UICollectionView!
    private var switchedAccount: Bool = false
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!
    private var collectionViewHeightConstraint: NSLayoutConstraint?
    
    private var visibleOtherAccounts: [MAccount] {
        Array(otherAccounts.prefix(max(0, switchAccountMaxAccountsShown - 1)))
    }

    private var shouldShowAllWalletsRow: Bool {
        otherAccounts.count > visibleOtherAccounts.count
    }
    
    private var calculatedHeight: CGFloat {
        var height = actionRowHeight + accountRowHeight
        if !visibleOtherAccounts.isEmpty {
            height += switchAccountDividerHeight
            height += CGFloat(visibleOtherAccounts.count) * accountRowHeight
            if shouldShowAllWalletsRow {
                height += actionRowHeight
            }
        }
        return height
    }
    
    // MARK: - Init
    
    public init(iconColor: UIColor) {
        self.activeAccount = AccountStore.account!
        self.otherAccounts = AccountStore.orderedAccounts.filter { $0.id != AccountStore.accountId }
        self.iconColor = iconColor
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    
    public override func loadView() {
        super.loadView()
        view.backgroundColor = .clear
        setupViews()
        configureDataSource()
        applySnapshot()
    }
    
    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateCollectionHeight()
    }
    
    // MARK: - Tab Bar Icon
    
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
    
    // MARK: - Setup
    
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
        
        let layout = UICollectionViewCompositionalLayout { [weak self] sectionIndex, env in
            self?.layoutSection(for: sectionIndex, environment: env)
        }
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.delegate = self
        collectionView.contentInset.bottom = 16
        collectionView.layer.cornerRadius = menuCornerRadius
        collectionView.bounces = false
        collectionView.isScrollEnabled = false
        collectionView.backgroundColor = .clear
        collectionView.isOpaque = false
        collectionView.backgroundView = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
        collectionView.delaysContentTouches = false
        collectionView.allowsSelection = true
        
        view.addSubview(collectionView)
        let heightConstraint = collectionView.heightAnchor.constraint(equalToConstant: calculatedHeight)
        heightConstraint.priority = .defaultHigh
        collectionViewHeightConstraint = heightConstraint
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            collectionView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -68),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            collectionView.widthAnchor.constraint(equalToConstant: 248),
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
        
        Haptics.prepare(.selection)
        updateTheme()
    }
    
    private func configureDataSource() {
        let accountRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, String> { cell, _, accountId in
            let accountContext = AccountContext(accountId: accountId)
            cell.configurationUpdateHandler = { cell, state in
                cell.contentConfiguration = UIHostingConfiguration {
                    AccountListCell(
                        accountContext: accountContext,
                        isReordering: state.isEditing,
                        showCurrentAccountHighlight: true,
                        showBalance: false
                    )
                }
                .background {
                    SwitchAccountCellBackground(isHighlighted: state.isHighlighted)
                }
                .margins(.horizontal, 12)
                .margins(.vertical, 10)
            }
        }
        let addAccountRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, Void> { cell, _, _ in
            cell.configurationUpdateHandler = { cell, state in
                cell.contentConfiguration = UIHostingConfiguration {
                    ActionRowView(
                        title: lang("Add Account"),
                        icon: Image.airBundle("AddAccountIcon")
                    )
                }
                .background {
                    SwitchAccountCellBackground(isHighlighted: state.isHighlighted)
                }
                .margins(.leading, 0)
                .margins(.trailing, 12)
                .margins(.vertical, 0)
            }
        }
        let showAllWalletsRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, Void> { cell, _, _ in
            cell.configurationUpdateHandler = { cell, state in
                cell.contentConfiguration = UIHostingConfiguration {
                    ActionRowView(
                        title: lang("Show All"),
                        icon: Image(systemName: "ellipsis"),
                    )
                }
                .background {
                    SwitchAccountCellBackground(isHighlighted: state.isHighlighted)
                }
                .margins(.leading, 0)
                .margins(.trailing, 12)
                .margins(.vertical, 0)
            }
        }
        let dividerRegistration = UICollectionView.CellRegistration<UICollectionViewCell, Void> { cell, _, _ in
            cell.contentView.backgroundColor = WTheme.backgroundReverse.withAlphaComponent(0.1)
            cell.backgroundColor = .clear
            cell.isUserInteractionEnabled = false
        }
        
        dataSource = UICollectionViewDiffableDataSource<Section, Item>(collectionView: collectionView) { collectionView, indexPath, item in
            switch item {
            case .addAccount:
                return collectionView.dequeueConfiguredReusableCell(using: addAccountRegistration, for: indexPath, item: ())
            case .showAllWallets:
                return collectionView.dequeueConfiguredReusableCell(using: showAllWalletsRegistration, for: indexPath, item: ())
            case .activeAccount(let account), .otherAccount(let account):
                return collectionView.dequeueConfiguredReusableCell(using: accountRegistration, for: indexPath, item: account.id)
            case .divider:
                return collectionView.dequeueConfiguredReusableCell(using: dividerRegistration, for: indexPath, item: ())
            }
        }
    }
    
    private func applySnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        
        // Active section
        snapshot.appendSections([.activeSection])
        snapshot.appendItems([.addAccount, .activeAccount(activeAccount)], toSection: .activeSection)
        
        // Divider and other accounts
        if !visibleOtherAccounts.isEmpty {
            snapshot.appendSections([.divider])
            snapshot.appendItems([.divider], toSection: .divider)
            
            snapshot.appendSections([.otherAccounts])
            snapshot.appendItems(visibleOtherAccounts.map { .otherAccount($0) }, toSection: .otherAccounts)
            if shouldShowAllWalletsRow {
                snapshot.appendItems([.showAllWallets], toSection: .otherAccounts)
            }
        }
        
        dataSource.apply(snapshot, animatingDifferences: false)
        updateCollectionHeight()
    }
    
    private func layoutSection(for sectionIndex: Int, environment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection? {
        let sections = dataSource?.snapshot().sectionIdentifiers ?? [.activeSection, .divider, .otherAccounts]
        guard sectionIndex < sections.count else { return nil }
        switch sections[sectionIndex] {
        case .divider:
            let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(switchAccountDividerHeight))
            let item = NSCollectionLayoutItem(layoutSize: itemSize)
            let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(switchAccountDividerHeight))
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])
            return NSCollectionLayoutSection(group: group)
        case .activeSection, .otherAccounts:
            var configuration = UICollectionLayoutListConfiguration(appearance: .plain)
            configuration.headerMode = .none
            configuration.backgroundColor = .clear
            configuration.separatorConfiguration.color = WTheme.separator
            configuration.separatorConfiguration.bottomSeparatorInsets.leading = 62
            configuration.itemSeparatorHandler = { [weak self] indexPath, separatorConfiguration in
                guard let self else { return separatorConfiguration }
                let lastIndex = self.collectionView.numberOfItems(inSection: indexPath.section) - 1
                guard indexPath.item == lastIndex, lastIndex >= 0 else { return separatorConfiguration }
                var separatorConfiguration = separatorConfiguration
                separatorConfiguration.bottomSeparatorVisibility = .hidden
                return separatorConfiguration
            }
            return NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: environment)
        }
    }
    
    private func updateCollectionHeight() {
        collectionView.collectionViewLayout.invalidateLayout()
        collectionView.layoutIfNeeded()
        let contentHeight = collectionView.collectionViewLayout.collectionViewContentSize.height
        collectionViewHeightConstraint?.constant = contentHeight > 0 ? contentHeight : calculatedHeight
    }
    
    // MARK: - Theme
    
    public override func updateTheme() {}
    
    public override var prefersStatusBarHidden: Bool { true }
    
    // MARK: - Actions
    
    @objc private func backPressed() {
        dismiss(animated: false)
    }
    
    @objc private func handleLongPressGesture(_ recognizer: UILongPressGestureRecognizer) {
        let location = recognizer.location(in: collectionView)
        
        switch recognizer.state {
        case .changed:
            if let indexPath = collectionView.indexPathForItem(at: location),
               let cell = collectionView.cellForItem(at: indexPath) {
                for it in collectionView.visibleCells {
                    if it == cell, !it.isHighlighted {
                        Haptics.play(.selection)
                    }
                    it.isHighlighted = it == cell
                }
            } else {
                if collectionView.visibleCells.contains(where: { $0.isHighlighted }) {
                    Haptics.play(.selection)
                }
                unhighlightAllCells()
            }
        case .ended:
            if let indexPath = collectionView.indexPathForItem(at: location) {
                handleSelection(at: indexPath)
                unhighlightAllCells()
            }
        default:
            break
        }
    }
    
    // MARK: - Animations
    
    public override func viewWillAppear(_ animated: Bool) {
        let collectionHeight = collectionViewHeightConstraint?.constant ?? calculatedHeight
        if IOS_26_MODE_ENABLED {
            collectionView.transform = .init(translationX: 0, y: collectionHeight / 2 - 30).scaledBy(x: 0.25, y: 0.25)
        } else {
            collectionView.transform = .init(translationX: 60.0, y: collectionHeight / 2 - 30).scaledBy(x: 0.25, y: 0.25)
        }
        
        UIView.transition(with: self.view, duration: 0.2) { [self] in
            blurView.alpha = 1
        }
        UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.75, initialSpringVelocity: 0.2) { [self] in
            collectionView.transform = .identity
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
        let collectionHeight = collectionViewHeightConstraint?.constant ?? calculatedHeight
        let targetColor = switchedAccount ? WTheme.secondaryLabel : iconColor
        UIView.animate(withDuration: duration, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.2) { [self] in
            if flag {
                collectionView.transform = .init(translationX: 60.0, y: collectionHeight / 2 - 30).scaledBy(x: 0.25, y: 0.25)
            }
            tabBarIcon.transform = .identity
            collectionView.alpha = 0
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
        for cell in collectionView.visibleCells {
            cell.isHighlighted = false
        }
    }
    
    private func switchAccount(to account: MAccount) {
        switchedAccount = true
        Task {
            do {
                _ = try await AccountStore.activateAccount(accountId: account.id)
                self.dismiss(animated: false) {
                    AppActions.showHome(popToRoot: true)
                }
            } catch {
                fatalError("failed to activate account: \(account.id)")
            }
        }
    }
    
    private func handleSelection(at indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }
        
        switch item {
        case .addAccount:
            addAccountSelected()
        case .showAllWallets:
            showAllWalletsSelected()
        case .activeAccount(let account):
            switchAccount(to: account)
        case .otherAccount(let account):
            switchAccount(to: account)
        case .divider:
            break
        }
    }
    
    private func addAccountSelected() {
        dismiss(animated: false) {
            AppActions.showAddWallet(showCreateWallet: true, showSwitchToOtherVersion: true)
        }
    }

    private func showAllWalletsSelected() {
        dismiss(animated: false) {
            AppActions.showWalletSettings()
        }
    }
}

extension SwitchAccountVC: UICollectionViewDelegate {
    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        handleSelection(at: indexPath)
    }
}

private struct ActionRowView: View {

    var title: String
    var icon: Image

    var body: some View {
        HStack(spacing: 0) {
            iconView
                .frame(width: 62)
            Text(title)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(Color.air.primaryLabel)
                .lineLimit(1)
                .allowsTightening(true)
        }
        .padding(.vertical, actionRowVerticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var iconView: some View {
        icon
            .renderingMode(.template)
            .foregroundStyle(Color.air.tint)
            .frame(width: actionRowIconSize, height: actionRowIconSize)
            .font(.system(size: 18, weight: .regular))
    }
}

private struct SwitchAccountCellBackground: View {
    var isHighlighted: Bool
    
    var body: some View {
        Rectangle()
            .fill(isHighlighted ? Color.air.highlight : .clear)
    }
}
