import UIKit
import UIComponents
import WalletContext
import WalletCore

/// The device's MyPulse notification choice and the digest's hour, which the digest sheet changes
@MainActor
protocol AgentDigestNotificationSettings: AnyObject {
    var mode: AgentNewsNotificationSettings.Mode { get }
    var digestHour: Int { get }
    func setMode(_ mode: AgentNewsNotificationSettings.Mode) async -> AgentNewsNotificationSettings.Outcome
    func setDigestHour(_ hour: Int) async -> AgentNewsNotificationSettings.Outcome
}

extension AgentNewsNotificationSettings: AgentDigestNotificationSettings {}

/// The digest sheet's state. A notification choice shows once the settings take it: while one is applied no other can
/// be picked, and one turned down keeps the previous choice.
@MainActor
final class AgentDigestSettingsModel {
    static let hours = Array(0..<24)
    static let modes: [AgentNewsNotificationSettings.Mode] = [.off, .digest, .news]

    private(set) var mode: AgentNewsNotificationSettings.Mode { didSet { onChange?() } }
    private(set) var digestHour: Int { didSet { onChange?() } }
    /// The choice being applied
    private(set) var pendingMode: AgentNewsNotificationSettings.Mode? { didSet { onChange?() } }
    /// An hour is being applied
    private(set) var isApplyingHour = false { didSet { onChange?() } }
    /// The system turned notifications down for the app at the last choice that needs them
    private(set) var isPermissionDenied = false { didSet { onChange?() } }
    var onChange: (() -> Void)?

    private let settings: AgentDigestNotificationSettings
    private let showError: () -> Void

    init(
        settings: AgentDigestNotificationSettings,
        showError: @escaping () -> Void = { AppActions.showError(error: ApiAnyDisplayError.unexpected) }
    ) {
        self.settings = settings
        self.showError = showError
        mode = settings.mode
        digestHour = settings.digestHour
    }

    func selectMode(_ mode: AgentNewsNotificationSettings.Mode) async {
        guard pendingMode == nil, mode != self.mode else { return }
        pendingMode = mode
        let outcome = await settings.setMode(mode)
        pendingMode = nil
        self.mode = settings.mode
        isPermissionDenied = outcome == .permissionDenied
        if outcome == .failed { showError() }
    }

    /// The settings keep a new hour also when applying it fails, and apply it again at the next start, so the sheet
    /// shows the kept hour next to the error
    func selectHour(_ hour: Int) async {
        guard !isApplyingHour, hour != digestHour else { return }
        isApplyingHour = true
        digestHour = hour
        let outcome = await settings.setDigestHour(hour)
        digestHour = settings.digestHour
        isApplyingHour = false
        if outcome == .failed { showError() }
    }

    static func formatHour(_ hour: Int) -> String {
        String(format: "%02d:00", hour)
    }

    static func title(of mode: AgentNewsNotificationSettings.Mode) -> String {
        switch mode {
        case .off: lang("$agent_digest_notifications_off")
        case .digest: lang("$agent_digest_notifications_daily")
        case .news: lang("$agent_digest_notifications_every")
        }
    }

    func hint(of mode: AgentNewsNotificationSettings.Mode) -> String {
        switch mode {
        case .off: lang("$agent_digest_notifications_off_hint")
        case .digest: L10n.agentDigestNotificationsDailyHint(time: Self.formatHour(digestHour))
        case .news: lang("$agent_digest_notifications_every_hint")
        }
    }
}

/// The digest's hour and the choice of MyPulse notifications in a bottom sheet as tall as its content, under the
/// header the app's sheets have, with Done at its foot
@MainActor
final class AgentDigestSettingsSheetVC: WViewController {
    private enum Metrics {
        static let sectionInset: CGFloat = 16
        static let rowInset: CGFloat = IOS_26_MODE_ENABLED ? 20 : 16
        static let textInset: CGFloat = sectionInset + rowInset
    }

    private let model: AgentDigestSettingsModel
    private let navigationHeader = NavigationHeader2()
    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private let hourButton = UIButton(type: .system)
    private let enableButton = UIButton(type: .system)
    private let hourRow = UIStackView()
    private var modeRows: [AgentNewsNotificationSettings.Mode: ModeRow] = [:]
    private let permissionSection = UIStackView()
    private let doneButton = WButton(style: .primary)

    init(model: AgentDigestSettingsModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Shows the sheet over `presenter`, in its own navigation for the header
    static func present(over presenter: UIViewController, settings: AgentDigestNotificationSettings = AgentNewsNotificationSettings.shared) {
        guard presenter.presentedViewController == nil else { return }
        let navigation = WNavigationController(rootViewController: AgentDigestSettingsSheetVC(model: AgentDigestSettingsModel(settings: settings)))
        presenter.present(navigation, animated: true)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationHeader.setTitle(lang("$agent_digest_settings_title"))
        navigationItem.titleView = navigationHeader
        addCloseNavigationItemIfNeeded()
        configureSheetWithOpaqueBackground(color: .air.sheetBackground)
        configureViews()
        model.onChange = { [weak self] in self?.update() }
        update()
        updateHourRowAxis()
        if #available(iOS 17.0, *) {
            registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (controller: AgentDigestSettingsSheetVC, _) in
                controller.updateButtonFonts()
            }
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if #unavailable(iOS 17.0) {
            guard previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory else { return }
            updateButtonFonts()
        }
    }

    private func updateButtonFonts() {
        updateHourRowAxis()
        hourButton.setNeedsUpdateConfiguration()
        enableButton.setNeedsUpdateConfiguration()
        view.setNeedsLayout()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateDetents()
    }

    /// As tall as the content under the header, up to the screen, where the content scrolls
    private func updateDetents() {
        guard let navigationController, let sheet = navigationController.sheetPresentationController else { return }
        let height = stackView.systemLayoutSizeFitting(
            CGSize(width: view.bounds.width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height + navigationController.navigationBar.frame.maxY
        guard abs(preferredContentSize.height - height) > 0.5 else { return }
        preferredContentSize.height = height
        sheet.animateChanges {
            sheet.detents = [.custom(identifier: .init("agentDigestSettings")) { context in
                min(height, context.maximumDetentValue)
            }]
        }
    }

    private func update() {
        var configuration = hourButton.configuration
        configuration?.title = AgentDigestSettingsModel.formatHour(model.digestHour)
        hourButton.configuration = configuration
        hourButton.accessibilityValue = AgentDigestSettingsModel.formatHour(model.digestHour)
        hourButton.menu = makeHourMenu()
        hourButton.isEnabled = !model.isApplyingHour
        for (mode, row) in modeRows {
            row.configure(
                hint: model.hint(of: mode),
                isSelected: model.mode == mode,
                isPending: model.pendingMode == mode,
                isEnabled: model.pendingMode == nil
            )
        }
        permissionSection.isHidden = !model.isPermissionDenied
        view.setNeedsLayout()
    }

    /// The hour goes under its title at the accessibility text sizes, where the two no longer fit side by side
    private func updateHourRowAxis() {
        let isStacked = traitCollection.preferredContentSizeCategory.isAccessibilityCategory
        hourRow.axis = isStacked ? .vertical : .horizontal
        hourRow.alignment = isStacked ? .leading : .center
    }

    private func makeHourMenu() -> UIMenu {
        UIMenu(children: AgentDigestSettingsModel.hours.map { hour in
            UIAction(title: AgentDigestSettingsModel.formatHour(hour), state: hour == model.digestHour ? .on : .off) { [weak self] _ in
                guard let self else { return }
                Task { await self.model.selectHour(hour) }
            }
        })
    }

    private func configureViews() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = false
        view.addSubview(scrollView)
        stackView.axis = .vertical
        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stackView)

        let text = makeLabel(lang("$agent_digest_settings_text"), style: .body, color: .air.secondaryLabel)
        stackView.addArrangedSubview(inset(text, top: 8, bottom: 24, horizontal: Metrics.textInset))

        let hourTitle = makeLabel(lang("$agent_digest_time"), style: .body, color: .label)
        hourTitle.isAccessibilityElement = false
        var hourConfiguration = UIButton.Configuration.plain()
        hourConfiguration.baseForegroundColor = .air.secondaryLabel
        hourConfiguration.image = UIImage(systemName: "chevron.up.chevron.down", withConfiguration: UIImage.SymbolConfiguration(textStyle: .footnote))
        hourConfiguration.imagePlacement = .trailing
        hourConfiguration.imagePadding = 4
        hourConfiguration.contentInsets = .zero
        hourConfiguration.titleTextAttributesTransformer = Self.makeBodyFontTransformer(for: hourButton)
        hourButton.configuration = hourConfiguration
        hourButton.showsMenuAsPrimaryAction = true
        hourButton.accessibilityLabel = lang("$agent_digest_time")
        hourButton.accessibilityIdentifier = "AgentDigestHour"
        hourButton.setContentHuggingPriority(.required, for: .horizontal)
        hourButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        hourRow.addArrangedSubview(hourTitle)
        hourRow.addArrangedSubview(hourButton)
        hourRow.spacing = 8
        hourRow.isLayoutMarginsRelativeArrangement = true
        hourRow.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 11, leading: Metrics.rowInset, bottom: 11, trailing: Metrics.rowInset)
        hourRow.heightAnchor.constraint(greaterThanOrEqualToConstant: S.sectionItemHeight).isActive = true
        stackView.addArrangedSubview(makeSection([hourRow]))
        let timeZone = makeLabel(lang("$agent_digest_time_zone"), style: .footnote, color: .air.secondaryLabel)
        stackView.addArrangedSubview(inset(timeZone, top: 7, bottom: 24, horizontal: Metrics.textInset))

        let header = makeLabel(
            IOS_26_MODE_ENABLED ? lang("Notifications") : lang("Notifications").uppercased(),
            style: .sectionHeader,
            color: .air.secondaryLabel
        )
        header.accessibilityTraits = .header
        // A one-word header shrinks to its line rather than breaking inside the word
        header.numberOfLines = 1
        header.adjustsFontSizeToFitWidth = true
        header.minimumScaleFactor = 0.5
        stackView.addArrangedSubview(inset(header, top: 0, bottom: 5, horizontal: Metrics.textInset))
        let rows = AgentDigestSettingsModel.modes.map { mode in
            let row = ModeRow(title: AgentDigestSettingsModel.title(of: mode))
            row.accessibilityIdentifier = "AgentDigestMode-\(mode.rawValue)"
            row.addAction(UIAction { [weak self] _ in
                guard let self else { return }
                Task { await self.model.selectMode(mode) }
            }, for: .touchUpInside)
            modeRows[mode] = row
            return row
        }
        stackView.addArrangedSubview(makeSection(rows))

        let disabled = makeLabel(lang("Notifications are disabled"), style: .bodyStrong, color: .label)
        let enable = enableButton
        var enableConfiguration = UIButton.Configuration.plain()
        enableConfiguration.title = lang("Enable in Settings")
        enableConfiguration.contentInsets = .zero
        enableConfiguration.titleAlignment = .leading
        enableConfiguration.titleTextAttributesTransformer = Self.makeBodyFontTransformer(for: enable)
        enable.configuration = enableConfiguration
        enable.contentHorizontalAlignment = .leading
        enable.addAction(UIAction { _ in
            guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
            UIApplication.shared.open(url)
        }, for: .touchUpInside)
        permissionSection.addArrangedSubview(makeSection([
            inset(disabled, top: 11, bottom: 11, horizontal: Metrics.rowInset),
            inset(enable, top: 11, bottom: 11, horizontal: Metrics.rowInset),
        ]))
        permissionSection.axis = .vertical
        permissionSection.isLayoutMarginsRelativeArrangement = true
        permissionSection.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 24, leading: 0, bottom: 0, trailing: 0)
        permissionSection.isHidden = true
        stackView.addArrangedSubview(permissionSection)

        doneButton.setTitle(lang("Done"), for: .normal)
        doneButton.accessibilityIdentifier = "AgentDigestDone"
        doneButton.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .touchUpInside)
        stackView.addArrangedSubview(inset(doneButton, top: 24, bottom: 16, horizontal: Metrics.sectionInset))

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor),
        ])
    }

    /// A button title in the body font at the button's own text size, which it takes again as the size changes
    private static func makeBodyFontTransformer(for button: UIButton) -> UIConfigurationTextAttributesTransformer {
        UIConfigurationTextAttributesTransformer { [weak button] attributes in
            var attributes = attributes
            attributes.font = WTypography.uiFont(.body, scaling: .dynamic, compatibleWith: button?.traitCollection)
            return attributes
        }
    }

    private func makeLabel(_ text: String, style: WTextStyle, color: UIColor) -> UILabel {
        let label = UILabel()
        label.text = text
        label.applyTextStyle(style, scaling: .dynamic)
        label.textColor = color
        label.numberOfLines = 0
        return label
    }

    private func inset(_ view: UIView, top: CGFloat, bottom: CGFloat, horizontal: CGFloat) -> UIView {
        let container = UIStackView(arrangedSubviews: [view])
        container.isLayoutMarginsRelativeArrangement = true
        container.directionalLayoutMargins = NSDirectionalEdgeInsets(top: top, leading: horizontal, bottom: bottom, trailing: horizontal)
        return container
    }

    /// The app's inset section: rows on a rounded grouped background, a separator between rows
    private func makeSection(_ rows: [UIView]) -> UIView {
        let section = UIStackView()
        section.axis = .vertical
        section.backgroundColor = .air.groupedItem
        section.layer.cornerRadius = S.insetSectionCornerRadius
        section.layer.cornerCurve = .continuous
        section.clipsToBounds = true
        for (index, row) in rows.enumerated() {
            if index > 0 {
                let separator = UIView()
                separator.backgroundColor = .air.separator
                separator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale).isActive = true
                let container = UIStackView(arrangedSubviews: [separator])
                container.isLayoutMarginsRelativeArrangement = true
                container.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: Metrics.rowInset, bottom: 0, trailing: 0)
                section.addArrangedSubview(container)
            }
            section.addArrangedSubview(row)
        }
        return inset(section, top: 0, bottom: 0, horizontal: Metrics.sectionInset)
    }
}

/// A notification choice: its title, its hint and the mark of the current choice, or a spinner while it is applied
private final class ModeRow: UIControl {
    private let titleLabel = UILabel()
    private let hintLabel = UILabel()
    private let markView = UIImageView(image: UIImage(systemName: "checkmark", withConfiguration: UIImage.SymbolConfiguration(textStyle: .body, scale: .medium)))
    private let spinner = UIActivityIndicatorView(style: .medium)

    init(title: String) {
        super.init(frame: .zero)
        titleLabel.text = title
        titleLabel.applyTextStyle(.body, scaling: .dynamic)
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 0
        hintLabel.applyTextStyle(.footnote, scaling: .dynamic)
        hintLabel.textColor = .air.secondaryLabel
        hintLabel.numberOfLines = 0
        markView.tintColor = .tintColor
        markView.contentMode = .center
        let texts = UIStackView(arrangedSubviews: [titleLabel, hintLabel])
        texts.axis = .vertical
        texts.spacing = 2
        let mark = UIView()
        for view in [markView, spinner] as [UIView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            mark.addSubview(view)
            NSLayoutConstraint.activate([
                view.centerXAnchor.constraint(equalTo: mark.centerXAnchor),
                view.centerYAnchor.constraint(equalTo: mark.centerYAnchor),
            ])
        }
        let row = UIStackView(arrangedSubviews: [texts, mark])
        row.spacing = 12
        row.alignment = .center
        row.isUserInteractionEnabled = false
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            mark.widthAnchor.constraint(equalToConstant: 24),
            mark.heightAnchor.constraint(equalToConstant: 24),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 60),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: IOS_26_MODE_ENABLED ? 20 : 16),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -(IOS_26_MODE_ENABLED ? 20 : 16)),
        ])
        isAccessibilityElement = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet { backgroundColor = isHighlighted ? .air.highlight : .clear }
    }

    func configure(hint: String, isSelected: Bool, isPending: Bool, isEnabled: Bool) {
        hintLabel.text = hint
        markView.isHidden = !isSelected || isPending
        if isPending { spinner.startAnimating() } else { spinner.stopAnimating() }
        self.isEnabled = isEnabled
        accessibilityLabel = [titleLabel.text, hint].compactMap { $0 }.joined(separator: ", ")
        accessibilityTraits = isSelected ? [.button, .selected] : .button
    }
}
