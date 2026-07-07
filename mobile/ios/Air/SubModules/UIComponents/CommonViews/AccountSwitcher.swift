import ContextMenuKit
import Dependencies
import SwiftUI
import UIKit
import WalletCore
import WalletContext

private let menuWidth: CGFloat = 286
private let menuRowHeight: CGFloat = 60
private let menuHorizontalPadding: CGFloat = 18
private let menuVerticalPadding: CGFloat = 10
private let buttonHeight: CGFloat = 44
private let buttonIconSize: CGFloat = 36
private let buttonAvatarWidth: CGFloat = 36
private let buttonChevronWidth: CGFloat = 66
private let buttonMinimumHitWidth: CGFloat = 44

public struct AccountSwitcherConfiguration: Equatable, Sendable {
    public var accountSupport: AccountSwitcherAccountSupport
    public var requiresPositiveBalance: Bool

    public init(accountSupport: AccountSwitcherAccountSupport, requiresPositiveBalance: Bool = false) {
        self.accountSupport = accountSupport
        self.requiresPositiveBalance = requiresPositiveBalance
    }

    @MainActor
    public func switchableAccounts(accountStore: _AccountStore, balanceDataStore: _BalanceDataStore) -> [MAccount] {
        accountStore.orderedAccounts.filter { account in
            isAccountSwitchable(account, balanceDataStore: balanceDataStore)
        }
    }

    @MainActor
    public func isAccountSwitchable(_ account: MAccount, balanceDataStore: _BalanceDataStore) -> Bool {
        guard accountSupport.isSupported(by: account) else {
            return false
        }
        if requiresPositiveBalance {
            guard let totalBalance = balanceDataStore.balanceTotals(accountId: account.id)?.totalBalance else {
                return false
            }
            return totalBalance.amount > 0
        }
        return true
    }
}

public enum AccountSwitcherAccountSupport: Equatable, Sendable {
    case send
    case swap
    case walletConnectPay

    @MainActor
    func isSupported(by account: MAccount) -> Bool {
        switch self {
        case .send:
            account.supportsSend
        case .swap:
            account.supportsSwap
        case .walletConnectPay:
            account.supportsWalletConnectPay
        }
    }
}

@MainActor
public final class AccountSwitcher {
    public let button = AccountSwitcherButton()
    public let barButtonItem: UIBarButtonItem

    private let configuration: AccountSwitcherConfiguration
    private let onSelect: (String) -> Void
    private var selectedAccountId: String?
    private var isEnabled = true
    private var interaction: ContextMenuInteraction?

    @Dependency(\.accountStore) private var accountStore
    @Dependency(\.balanceDataStore) private var balanceDataStore

    public init(configuration: AccountSwitcherConfiguration, onSelect: @escaping (String) -> Void) {
        self.configuration = configuration
        self.onSelect = onSelect
        self.barButtonItem = UIBarButtonItem(customView: button)
        self.barButtonItem.width = buttonChevronWidth

        let interaction = ContextMenuInteraction(
            triggers: [.tap, .longPress],
            configurationProvider: { [weak self] _ in
                self?.makeMenuConfiguration() ?? ContextMenuConfiguration(
                    rootPage: ContextMenuPage(items: []),
                    backdrop: .dimmed(alpha: 0.18)
                )
            }
        )
        interaction.attach(to: button)
        self.interaction = interaction
    }

    public func update(selectedAccountId: String, isEnabled: Bool = true) {
        self.selectedAccountId = selectedAccountId
        self.isEnabled = isEnabled

        let account = accountStore.get(accountId: selectedAccountId)
        let hasAlternativeAccounts = hasAlternativeAccounts(selectedAccountId: selectedAccountId)
        let width: CGFloat = hasAlternativeAccounts ? buttonChevronWidth : buttonAvatarWidth

        button.configure(account: account, showsChevron: hasAlternativeAccounts)
        button.setWidth(width)
        button.isUserInteractionEnabled = isEnabled && hasAlternativeAccounts
        button.alpha = 1
        barButtonItem.width = width
    }

    public func hasAlternativeAccounts(selectedAccountId: String) -> Bool {
        switchableAccounts.contains { $0.id != selectedAccountId }
    }

    private var switchableAccounts: [MAccount] {
        configuration.switchableAccounts(accountStore: accountStore, balanceDataStore: balanceDataStore)
    }

    private func makeMenuConfiguration() -> ContextMenuConfiguration {
        guard let selectedAccountId, isEnabled else {
            return ContextMenuConfiguration(rootPage: ContextMenuPage(items: []), backdrop: .dimmed(alpha: 0.18))
        }

        let items: [ContextMenuItem] = switchableAccounts.map { account in
            .custom(makeMenuRow(account: account, selectedAccountId: selectedAccountId))
        }

        return ContextMenuConfiguration(
            rootPage: ContextMenuPage(items: items),
            backdrop: .dimmed(alpha: 0.18),
            style: ContextMenuStyle(minWidth: menuWidth, maxWidth: menuWidth)
        )
    }

    private func makeMenuRow(account: MAccount, selectedAccountId: String) -> ContextMenuCustomRow {
        .swiftUI(
            id: account.id,
            preferredWidth: menuWidth,
            sizing: .fixed(height: menuRowHeight),
            interaction: .selectable(handler: { [weak self] in
                guard account.id != selectedAccountId else { return }
                self?.onSelect(account.id)
            })
        ) { _ in
            AccountSwitcherMenuRow(
                account: account,
                isSelected: account.id == selectedAccountId
            )
            .padding(.horizontal, menuHorizontalPadding)
            .padding(.vertical, menuVerticalPadding)
        }
    }
}

private struct AccountSwitcherMenuRow: View {
    var account: MAccount
    var isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            AccountListCell(
                accountContext: AccountContext(accountId: account.id),
                isReordering: false,
                showCurrentAccountHighlight: false,
                showBalance: false
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
        }
    }
}

public final class AccountSwitcherButton: UIControl {
    private let iconView = IconView(size: buttonIconSize)
    private let chevronView = UIImageView(
        image: UIImage(
            systemName: "chevron.up.chevron.down",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        )
    )
    private var width: CGFloat = buttonChevronWidth
    private var widthConstraint: NSLayoutConstraint?

    override public init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public var intrinsicContentSize: CGSize {
        CGSize(width: width, height: buttonHeight)
    }

    override public func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let horizontalOutset = max(0, (buttonMinimumHitWidth - bounds.width) / 2)
        return bounds.insetBy(dx: -horizontalOutset, dy: 0).contains(point)
    }

    public func configure(account: MAccount?, showsChevron: Bool) {
        iconView.config(with: account)
        chevronView.isHidden = !showsChevron
        setWidth(showsChevron ? buttonChevronWidth : buttonAvatarWidth)
        accessibilityLabel = account?.displayName
    }

    public func setWidth(_ width: CGFloat) {
        guard abs(self.width - width) > 0.5 else { return }
        self.width = width
        frame.size = CGSize(width: width, height: buttonHeight)
        widthConstraint?.constant = width
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        frame = CGRect(x: 0, y: 0, width: width, height: buttonHeight)
        isAccessibilityElement = true
        accessibilityTraits = .button
        setContentHuggingPriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .vertical)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.isUserInteractionEnabled = false
        addSubview(iconView)

        chevronView.translatesAutoresizingMaskIntoConstraints = false
        chevronView.tintColor = .label
        chevronView.contentMode = .scaleAspectFit
        chevronView.isUserInteractionEnabled = false
        addSubview(chevronView)

        let widthConstraint = widthAnchor.constraint(equalToConstant: buttonChevronWidth)
        self.widthConstraint = widthConstraint

        NSLayoutConstraint.activate([
            widthConstraint,
            heightAnchor.constraint(equalToConstant: buttonHeight),
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevronView.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            chevronView.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevronView.widthAnchor.constraint(equalToConstant: 14),
            chevronView.heightAnchor.constraint(equalToConstant: 18),
        ])
    }
}
