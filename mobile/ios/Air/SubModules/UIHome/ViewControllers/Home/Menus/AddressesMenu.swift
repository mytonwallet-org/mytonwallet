import ContextMenuKit
import Foundation
import UIComponents
import UIKit
import WalletContext
import WalletCore

private let addressesMenuWidth: CGFloat = 294
private let addressRowHeight: CGFloat = 60

struct AddressesMenuContentRow {
    var chain: ApiChain
    var accountChain: AccountChain
}

@MainActor func makeAddressesMenuConfig(accountContext: AccountContext) -> () -> ContextMenuConfiguration {
    return {
        let visibleRows = accountContext.displayedChains.map { chain, accountChain in
            AddressesMenuContentRow(chain: chain, accountChain: accountChain)
        }
        let visibleChains = Set(visibleRows.map(\.chain))
        let hiddenRows = accountContext.orderedChains
            .filter { !visibleChains.contains($0.0) }
            .map { chain, accountChain in
                AddressesMenuContentRow(chain: chain, accountChain: accountChain)
            }

        var items: [ContextMenuItem] = [
            .action(
                ContextMenuAction(
                    title: lang("Share Wallet Link"),
                    icon: .airBundle("MenuShare28"),
                    handler: {
                        let shareLink = accountContext.shareLink
                        UIPasteboard.general.url = shareLink
                        AppActions.shareUrl(shareLink)
                    }
                )
            ),
            .separator,
        ]

        items.append(contentsOf: visibleRows.map { makeAddressRowItem(row: $0, accountContext: accountContext) })

        if !hiddenRows.isEmpty {
            items.append(.separator)
            items.append(
                .submenu(
                    ContextMenuSubmenu(
                        title: lang("All Chains"),
                        icon: makeHiddenChainsIcon(rows: hiddenRows),
                        makePage: {
                            var pageItems: [ContextMenuItem] = [
                                .back(
                                    ContextMenuBackAction(
                                        title: lang("Back"),
                                        icon: .airBundle("MenuBack")
                                    )
                                ),
                                .separator,
                            ]
                            pageItems.append(contentsOf: hiddenRows.map { makeAddressRowItem(row: $0, accountContext: accountContext) })
                            return ContextMenuPage(items: pageItems)
                        }
                    )
                )
            )
        }

        return ContextMenuConfiguration(
            rootPage: ContextMenuPage(items: items),
            backdrop: .none,
            style: ContextMenuStyle(
                minWidth: addressesMenuWidth,
                maxWidth: addressesMenuWidth,
                sourceSpacing: -32,
                animationSourceSpacing: 4,
                separatorHeight: 21
            )
        )
    }
}

@MainActor
private func makeAddressRowItem(row: AddressesMenuContentRow, accountContext: AccountContext) -> ContextMenuItem {
    let interaction: ContextMenuCustomRowInteraction
    if let domain = row.accountChain.domain {
        interaction = .submenu(
            allowsContentInteraction: true,
            makePage: {
                makeAddressDetailsPage(row: row, domain: domain)
            }
        )
    } else {
        interaction = .selectable(
            allowsContentInteraction: true,
            handler: {
                copyAddress(row: row)
            }
        )
    }

    return .custom(
        ContextMenuCustomRow(
            sizing: .fixed(height: addressRowHeight),
            interaction: interaction,
            makeContentView: { context in
                AddressMenuRowView(row: row, accountContext: accountContext, context: context)
            }
        )
    )
}

@MainActor
private func makeHiddenChainsIcon(rows: [AddressesMenuContentRow]) -> ContextMenuIcon? {
    let images = rows.prefix(3).map(\.chain.image)
    let contentWidth = 20 + CGFloat(images.count - 1) * 10
    let contentOffsetX = 4 + (40 - contentWidth) / 2
    guard let image = OverlappingIconStackView.makeImage(
        images: images,
        iconSize: 20,
        spacing: 10,
        cutoutGap: 1,
        canvasSize: CGSize(width: 44, height: 20),
        contentOffset: CGPoint(x: contentOffsetX, y: 0)
    ) else {
        return nil
    }
    return .image(image, renderingMode: .original)
}

@MainActor
private func makeAddressDetailsPage(row: AddressesMenuContentRow, domain: String) -> ContextMenuPage {
    ContextMenuPage(items: [
        .back(
            ContextMenuBackAction(
                title: lang("Back"),
                icon: .airBundle("MenuBack")
            )
        ),
        .separator,
        makeAddressValueRowItem(
            title: domain,
            subtitle: lang("Domain"),
            value: domain,
            toastMessage: L10n.chainDomainCopied(chain: row.chain.title)
        ),
        makeAddressValueRowItem(
            title: formatStartEndAddress(row.accountChain.address, prefix: 6, suffix: 6),
            subtitle: lang("Address"),
            value: row.accountChain.address,
            toastMessage: L10n.chainAddressCopied(chain: row.chain.title)
        ),
    ])
}

@MainActor
private func makeAddressValueRowItem(
    title: String,
    subtitle: String,
    value: String,
    toastMessage: String
) -> ContextMenuItem {
    .custom(
        ContextMenuCustomRow(
            sizing: .fixed(height: addressRowHeight),
            interaction: .selectable(handler: {
                copyValue(value, toastMessage: toastMessage)
            }),
            makeContentView: { _ in
                AddressValueMenuRowView(title: title, subtitle: subtitle)
            }
        )
    )
}

private enum AddressMenuAccessory {
    case copy
    case disclosure

    @MainActor var image: UIImage {
        switch self {
        case .copy:
            UIImage.airBundle("HomeCopy").withRenderingMode(.alwaysTemplate)
        case .disclosure:
            UIImage(
                systemName: "chevron.forward",
                withConfiguration: UIImage.SymbolConfiguration(
                    font: WTypography.uiFont(.title3, content: .technical)
                )
            )!.withRenderingMode(.alwaysTemplate)
        }
    }
}

@MainActor
private final class AddressMenuRowView: UIView {
    private let contentView = AddressMenuContentView()
    private let actionButton = UIButton(type: .system)
    private let row: AddressesMenuContentRow
    private let accountContext: AccountContext
    private let opensReceive: Bool
    private let context: ContextMenuCustomRowContext

    init(row: AddressesMenuContentRow, accountContext: AccountContext, context: ContextMenuCustomRowContext) {
        self.row = row
        self.accountContext = accountContext
        self.opensReceive = accountContext.account.supportsReceive
        self.context = context
        super.init(frame: .zero)

        let domain = row.accountChain.domain
        let displayedAddress = if let domain {
            "\(domain) \(formatStartEndAddress(row.accountChain.address, prefix: 0, suffix: 6))"
        } else {
            formatStartEndAddress(row.accountChain.address, prefix: 6, suffix: 6)
        }
        contentView.configure(
            image: row.chain.image,
            title: row.chain.title,
            subtitle: displayedAddress,
            accessory: domain == nil ? .copy : .disclosure
        )
        accessibilityLabel = [row.chain.title, displayedAddress].joined(separator: ", ")
        accessibilityHint = domain == nil ? lang("Copy Address") : lang("Details")

        let actionTitle = opensReceive ? lang("Receive") : lang("Open in Explorer")
        actionButton.translatesAutoresizingMaskIntoConstraints = false
        actionButton.setImage(
            UIImage.airBundle(opensReceive ? "HomeQR" : "HomeGlobe").withRenderingMode(.alwaysTemplate),
            for: .normal
        )
        actionButton.tintColor = .tintColor
        actionButton.accessibilityLabel = actionTitle
        actionButton.addAction(UIAction { [weak self] _ in
            self?.performAddressAction()
        }, for: .touchUpInside)
        accessibilityCustomActions = [
            UIAccessibilityCustomAction(
                name: actionTitle,
                target: self,
                selector: #selector(performAddressActionAccessibilityAction(_:))
            ),
        ]

        contentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentView)
        addSubview(actionButton)

        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentView.topAnchor.constraint(equalTo: topAnchor),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor),
            contentView.trailingAnchor.constraint(equalTo: actionButton.leadingAnchor),

            actionButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            actionButton.topAnchor.constraint(equalTo: topAnchor),
            actionButton.bottomAnchor.constraint(equalTo: bottomAnchor),
            actionButton.widthAnchor.constraint(equalToConstant: 40),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func performAddressActionAccessibilityAction(_: UIAccessibilityCustomAction) -> Bool {
        performAddressAction()
        return true
    }

    private func performAddressAction() {
        context.dismiss()
        if opensReceive {
            AppActions.showReceive(accountContext: accountContext, chain: row.chain)
        } else {
            let url = ExplorerHelper.addressUrl(chain: row.chain, address: row.accountChain.address)
            AppActions.openInBrowser(url)
        }
    }
}

@MainActor
private final class AddressMenuContentView: UIView {
    private let chainImageView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let accessoryImageView = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)

        chainImageView.translatesAutoresizingMaskIntoConstraints = false
        chainImageView.contentMode = .scaleAspectFit

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.applyTextStyle(.body)
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.applyTextStyle(.footnote, content: .technical)
        subtitleLabel.textColor = .air.secondaryLabel
        subtitleLabel.numberOfLines = 1
        subtitleLabel.lineBreakMode = .byTruncatingMiddle

        accessoryImageView.translatesAutoresizingMaskIntoConstraints = false
        accessoryImageView.tintColor = .air.secondaryLabel
        accessoryImageView.contentMode = .scaleAspectFit

        addSubview(chainImageView)
        addSubview(titleLabel)
        addSubview(subtitleLabel)
        addSubview(accessoryImageView)

        NSLayoutConstraint.activate([
            chainImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            chainImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            chainImageView.widthAnchor.constraint(equalToConstant: 40),
            chainImageView.heightAnchor.constraint(equalToConstant: 40),

            titleLabel.leadingAnchor.constraint(equalTo: chainImageView.trailingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: accessoryImageView.leadingAnchor, constant: -8),
            titleLabel.bottomAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.heightAnchor.constraint(equalToConstant: 20),

            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: accessoryImageView.leadingAnchor, constant: -8),
            subtitleLabel.topAnchor.constraint(equalTo: centerYAnchor, constant: 2),
            subtitleLabel.heightAnchor.constraint(equalToConstant: 18),

            accessoryImageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            accessoryImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            accessoryImageView.widthAnchor.constraint(equalToConstant: 24),
            accessoryImageView.heightAnchor.constraint(equalToConstant: 24),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(image: UIImage, title: String, subtitle: String, accessory: AddressMenuAccessory) {
        chainImageView.image = image
        titleLabel.text = title
        subtitleLabel.text = subtitle
        accessoryImageView.image = accessory.image
    }
}

@MainActor
private final class AddressValueMenuRowView: UIView {
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let copyImageView = UIImageView()

    init(title: String, subtitle: String) {
        super.init(frame: .zero)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.applyTextStyle(.body, content: .technical)
        titleLabel.textColor = .label
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.text = title

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.applyTextStyle(.footnote)
        subtitleLabel.textColor = .air.secondaryLabel
        subtitleLabel.text = subtitle

        copyImageView.translatesAutoresizingMaskIntoConstraints = false
        copyImageView.image = UIImage.airBundle("HomeCopy").withRenderingMode(.alwaysTemplate)
        copyImageView.tintColor = .air.secondaryLabel
        copyImageView.contentMode = .scaleAspectFit

        addSubview(titleLabel)
        addSubview(subtitleLabel)
        addSubview(copyImageView)

        accessibilityLabel = [title, subtitle].joined(separator: ", ")
        accessibilityHint = lang("Copy")

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: copyImageView.leadingAnchor, constant: -8),
            titleLabel.bottomAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.heightAnchor.constraint(equalToConstant: 20),

            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: copyImageView.leadingAnchor, constant: -8),
            subtitleLabel.topAnchor.constraint(equalTo: centerYAnchor, constant: 2),
            subtitleLabel.heightAnchor.constraint(equalToConstant: 18),

            copyImageView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            copyImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            copyImageView.widthAnchor.constraint(equalToConstant: 24),
            copyImageView.heightAnchor.constraint(equalToConstant: 24),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@MainActor
private func copyAddress(row: AddressesMenuContentRow) {
    let message = if row.accountChain.domain != nil {
        L10n.chainDomainCopied(chain: row.chain.title)
    } else {
        L10n.chainAddressCopied(chain: row.chain.title)
    }
    copyValue(row.accountChain.preferredCopyString, toastMessage: message)
}

@MainActor
private func copyValue(_ value: String, toastMessage: String) {
    UIPasteboard.general.string = value
    AppActions.showToast(icon: .animatedCopy, message: toastMessage)
    Haptics.play(.lightTap)
}
