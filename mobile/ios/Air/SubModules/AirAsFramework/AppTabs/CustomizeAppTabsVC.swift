import UIKit
import UIComponents
import UISettings
import WalletContext

final class CustomizeAppTabsVC: SettingsBaseVC {
    private var dragView: TwoZoneDragView<Item>!
    private var dragViewConstraints: [NSLayoutConstraint] = []
    private var currentAxis: TwoZoneAxis = .horizontal
    private var hintLabel: UILabel?

    private let resetButton: WButton = {
        let btn = WButton(style: .primary)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.setTitle(lang("Reset"), for: .normal)
        return btn
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = lang("Customize Tabs")
        view.backgroundColor = .air.groupedBackground
        setupResetButton()
        installDragView(axis: preferredAxis)
        updateResetButton()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        let newAxis = preferredAxis
        guard newAxis != currentAxis else { return }
        installDragView(axis: newAxis)
    }

    private var preferredAxis: TwoZoneAxis {
        traitCollection.horizontalSizeClass == .regular ? .vertical : .horizontal
    }

    private func setupResetButton() {
        view.addSubview(resetButton)
        NSLayoutConstraint.activate([
            resetButton.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            resetButton.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -16),
            resetButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor).withPriority(.defaultHigh),
        ])
        resetButton.addTarget(self, action: #selector(onResetTapped), for: .touchUpInside)
    }

    @objc private func onResetTapped() {
        AppTabManager.shared.resetToDefault()
        installDragView(axis: currentAxis)
        updateResetButton()
    }

    private func updateResetButton() {
        resetButton.isEnabled = AppTabManager.shared.orderedTabIds != AppTabManager.defaultTabIds
    }

    private func makeItems(from ids: [AppTabId]) -> [Item] {
        ids.compactMap { Item(id: $0) }
    }

    private func installDragView(axis: TwoZoneAxis) {
        let destIds = AppTabManager.shared.orderedTabIds
        let sourceIds = AppTabManager.shared.registeredTabIds.filter { !destIds.contains($0) }

        let dest = makeItems(from: destIds)
        let source = makeItems(from: sourceIds)

        dragView?.removeFromSuperview()
        hintLabel?.removeFromSuperview()
        NSLayoutConstraint.deactivate(dragViewConstraints)
        currentAxis = axis

        let smallHeightDeviceMode = UIScreen.main.bounds.height < 450
        
        var cfg: TwoZoneDragConfig<Item>
        if axis == .horizontal {
            cfg = TwoZoneDragConfig<Item>(
                axis: .horizontal,
                destMaxItems: 5,
                sourceColumnCount: 5,
                itemHeight: 54,
                itemSpacing: 0,
                separatorThickness: 60,
                destColumnWidth: 0,
                destMargins: UIEdgeInsets(top: 16, left: 4, bottom: 0, right: 4),
                destInsets: UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8),
                sourceInsets: UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8),
                tileProvider:  { item, context in
                    let tile = TileView()
                    tile.configure(title: item.title, icon: item.icon, context: context, isLocked: item.isLocked)
                    return tile
                }
            )
        } else {
            cfg = TwoZoneDragConfig<Item>(
                axis: .vertical,
                destMaxItems: 5,
                sourceColumnCount: 1,
                itemHeight: smallHeightDeviceMode ? 48 : 52,
                itemSpacing: smallHeightDeviceMode ? 3 : 4,
                separatorThickness: 16,
                destColumnWidth: 160,
                destInsets: .zero,
                sourceInsets: .zero,
                tileProvider: { item, context in
                    let tile = PillTileView()
                    tile.configure(title: item.title, icon: item.icon, context: context, isLocked: item.isLocked)
                    return tile
                }
            )
        }
        cfg.onReorderHaptic = { Haptics.play(.drag) }

        let newView = TwoZoneDragView<Item>(config: cfg)
        newView.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(newView, belowSubview: resetButton)

        if axis == .horizontal {
            dragViewConstraints = [
                newView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                newView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
                newView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
                newView.heightAnchor.constraint(equalToConstant: 216),
            ]
        } else {
            let destH = cfg.destInsets.vertical + 5 * cfg.itemHeight + 4 * cfg.itemSpacing
            dragViewConstraints = [
                newView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: smallHeightDeviceMode ? 0 : 16),
                newView.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
                newView.widthAnchor.constraint(equalToConstant: 350),
                newView.bottomAnchor.constraint(lessThanOrEqualTo: resetButton.topAnchor, constant: -8),
                newView.heightAnchor.constraint(equalToConstant: destH).withPriority(.defaultHigh)
            ]
        }

        dragViewConstraints += [
            resetButton.widthAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.widthAnchor, constant: -32),
            resetButton.widthAnchor.constraint(lessThanOrEqualTo: newView.widthAnchor),
            resetButton.widthAnchor.constraint(equalTo: view.safeAreaLayoutGuide.widthAnchor, constant: -32).withPriority(.defaultHigh),
        ]

        NSLayoutConstraint.activate(dragViewConstraints)
        newView.sourcePaletteScroll.backgroundColor = .air.groupedItem
        newView.sourcePaletteScroll.layer.cornerRadius = 26
        newView.sourcePaletteScroll.layer.cornerCurve = .continuous
        newView.sourcePaletteScroll.clipsToBounds = true

        if axis == .horizontal {
            let addLabel = UILabel()
            addLabel.translatesAutoresizingMaskIntoConstraints = false
            addLabel.text = lang("Add Tab")
            addLabel.font = .systemFont(ofSize: 17, weight: .medium)
            addLabel.textColor = .secondaryLabel
            addLabel.textAlignment = .center
            newView.separatorView.addSubview(addLabel)
            NSLayoutConstraint.activate([
                addLabel.centerXAnchor.constraint(equalTo: newView.separatorView.centerXAnchor),
                addLabel.centerYAnchor.constraint(equalTo: newView.separatorView.centerYAnchor),
            ])
        }

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = lang("Tap or drag to add tabs.")
        label.font = .systemFont(ofSize: 13, weight: .regular)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        view.addSubview(label)
        NSLayoutConstraint.activate([
            smallHeightDeviceMode ?
                label.bottomAnchor.constraint(equalTo: newView.sourcePaletteScroll.bottomAnchor, constant: -16) :
                label.topAnchor.constraint(equalTo: newView.sourcePaletteScroll.bottomAnchor, constant: 16),
            label.centerXAnchor.constraint(equalTo: newView.sourcePaletteScroll.centerXAnchor),
        ])
        hintLabel = label

        newView.load(dest: dest, source: source)

        newView.onDrop = { [weak self] destItems, _ in
            let newIds = destItems.map(\.id)
            AppTabManager.shared.setTabIds(newIds)
            self?.updateResetButton()
        }

        dragView = newView
    }
}

private struct Item: TwoZoneItem {
    let id: AppTabId
    let title: String
    let icon: UIImage
    var isLocked: Bool
    
    @MainActor
    init?(id: AppTabId) {
        guard let reg = AppTabManager.shared.registration(for: id) else { return nil }
        self.id = id
        self.title = reg.titleProvider()
        self.icon = reg.compactIcon
        self.isLocked = id.isRequired
    }
}

private class PillTileView: UIView {
    private let capsuleView = UIView()
    private let iconImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .center
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 17, weight: .regular)
        label.numberOfLines = 1
        return label
    }()
    private lazy var contentStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [iconImageView, titleLabel])
        stack.axis = .horizontal
        stack.spacing = 10
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        capsuleView.translatesAutoresizingMaskIntoConstraints = false
        capsuleView.layer.cornerCurve = .continuous
        addSubview(capsuleView)
        addSubview(contentStack)
        NSLayoutConstraint.activate([
            capsuleView.leadingAnchor.constraint(equalTo: leadingAnchor),
            capsuleView.trailingAnchor.constraint(equalTo: trailingAnchor),
            capsuleView.topAnchor.constraint(equalTo: topAnchor),
            capsuleView.bottomAnchor.constraint(equalTo: bottomAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 30),
            iconImageView.heightAnchor.constraint(equalToConstant: 30),
            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            contentStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            contentStack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        capsuleView.layer.cornerRadius = bounds.height / 2
    }

    func configure(title: String, icon: UIImage, context: TwoZoneItemContext, isLocked: Bool) {
        iconImageView.image = icon.withRenderingMode(.alwaysTemplate)
        titleLabel.text = title
        if isLocked {
            capsuleView.backgroundColor = .clear
            iconImageView.tintColor = .tertiaryLabel
            titleLabel.textColor = .tertiaryLabel
        } else if context == .dragging {
            capsuleView.backgroundColor = .clear
            iconImageView.tintColor = .tintColor
            titleLabel.textColor = .tintColor
        } else {
            capsuleView.backgroundColor = .secondarySystemGroupedBackground
            iconImageView.tintColor = .label
            titleLabel.textColor = .label
        }
    }
}

private class TileView: UIView {
    private let pillView = UIView()
    private let iconImageView: UIImageView = {
        let iv = UIImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.contentMode = .center
        return iv
    }()
    
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 10, weight: .medium)
        label.textAlignment = .center
        label.numberOfLines = 1
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.7
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        pillView.isHidden = true
        addSubview(pillView)
        addSubview(iconImageView)
        addSubview(titleLabel)
        NSLayoutConstraint.activate([
            iconImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconImageView.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            iconImageView.widthAnchor.constraint(equalToConstant: 28),
            iconImageView.heightAnchor.constraint(equalToConstant: 28),
            titleLabel.topAnchor.constraint(equalTo: iconImageView.bottomAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -6),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        pillView.frame = bounds
        pillView.layer.cornerRadius = pillView.bounds.height / 2
        pillView.layer.cornerCurve = .continuous
    }

    func configure(title: String, icon: UIImage, context: TwoZoneItemContext, isLocked: Bool) {
        titleLabel.text = title
        iconImageView.image = icon.withRenderingMode(.alwaysTemplate)

        if isLocked {
            pillView.isHidden = false
            iconImageView.tintColor = .tertiaryLabel
            titleLabel.textColor = .tertiaryLabel
        } else if context == .dragging {
            pillView.isHidden = true
            iconImageView.tintColor = .tintColor
            titleLabel.textColor = .tintColor
        } else {
            pillView.isHidden = false
            iconImageView.tintColor = .label
            titleLabel.textColor = .label
        }
    }
}
