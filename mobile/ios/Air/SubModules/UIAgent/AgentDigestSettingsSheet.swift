import UIKit
import UIComponents
import WalletContext
import WalletCore

/// The device's MyPulse notification choice and the digest's time, which the digest sheet changes
@MainActor
protocol AgentDigestNotificationSettings: AnyObject {
    var mode: AgentNewsNotificationSettings.Mode { get }
    var digestHour: Int { get }
    var digestMinute: Int { get }
    func setMode(_ mode: AgentNewsNotificationSettings.Mode) async -> AgentNewsNotificationSettings.Outcome
    func setDigestTime(hour: Int, minute: Int) async -> AgentNewsNotificationSettings.Outcome
}

extension AgentNewsNotificationSettings: AgentDigestNotificationSettings {}

/// The digest sheet's state. A notification choice and a time show at once. A choice or a time picked while another is
/// applied goes next across sheets, the last one picked winning; a choice the settings turn down gives way to the one they keep.
@MainActor
final class AgentDigestSettingsModel {
    static let hours = Array(0..<24)
    static let minutes = AgentNewsNotificationSettings.digestMinutes
    static let modes: [AgentNewsNotificationSettings.Mode] = [.off, .digest, .news]

    var mode: AgentNewsNotificationSettings.Mode { pendingState.queuedMode ?? pendingMode ?? settings.mode }
    var digestTime: DigestTime {
        pendingState.queuedTime ?? pendingState.time ?? DigestTime(hour: settings.digestHour, minute: settings.digestMinute)
    }
    var digestHour: Int { digestTime.hour }
    var digestMinute: Int { digestTime.minute }
    /// The choice being applied
    var pendingMode: AgentNewsNotificationSettings.Mode? { pendingState.mode }
    /// A time is being applied
    var isApplyingTime: Bool { pendingState.time != nil }
    /// The system turned notifications down for the app at the last choice that needs them
    var isPermissionDenied: Bool { pendingState.isPermissionDenied }
    var onChange: (() -> Void)? {
        get { pendingState.onChange }
        set {
            guard pendingState.owner === self else { return }
            pendingState.onChange = newValue
        }
    }

    private let settings: AgentDigestNotificationSettings
    private let pendingState: PendingState

    init(
        settings: AgentDigestNotificationSettings,
        pendingState: PendingState = .shared,
        showError: @escaping () -> Void = { AppActions.showError(error: ApiAnyDisplayError.unexpected) }
    ) {
        self.settings = settings
        self.pendingState = pendingState
        self.pendingState.owner = self
        self.pendingState.onChange = nil
        self.pendingState.showError = showError
        if pendingMode == nil { self.pendingState.isPermissionDenied = false }
    }

    func clearCallbacks() {
        guard pendingState.owner === self else { return }
        pendingState.owner = nil
        pendingState.onChange = nil
        pendingState.showError = nil
    }

    func selectMode(_ mode: AgentNewsNotificationSettings.Mode) async {
        guard mode != self.mode else { return }
        pendingState.isPermissionDenied = false
        guard pendingMode == nil else {
            pendingState.queuedMode = mode
            pendingState.onChange?()
            return
        }
        var nextMode: AgentNewsNotificationSettings.Mode? = mode
        while let mode = nextMode {
            pendingState.queuedMode = nil
            pendingState.mode = mode
            pendingState.onChange?()
            let outcome = await settings.setMode(mode)
            nextMode = pendingState.queuedMode
            // Only the last choice's outcome is told: an earlier one is already replaced
            guard nextMode == nil else { continue }
            pendingState.isPermissionDenied = outcome == .permissionDenied
            if outcome == .failed { pendingState.showError?() }
        }
        pendingState.mode = nil
        pendingState.onChange?()
    }

    func selectHour(_ hour: Int) async {
        await selectTime(DigestTime(hour: hour, minute: digestMinute))
    }

    func selectMinute(_ minute: Int) async {
        await selectTime(DigestTime(hour: digestHour, minute: minute))
    }

    /// The settings keep a new time also when applying it fails, and apply it again at the next start, so the sheet
    /// shows the kept time next to the error
    private func selectTime(_ time: DigestTime) async {
        guard time != digestTime else { return }
        guard !isApplyingTime else {
            pendingState.queuedTime = time
            pendingState.onChange?()
            return
        }
        var nextTime: DigestTime? = time
        while let time = nextTime {
            pendingState.queuedTime = nil
            pendingState.time = time
            pendingState.onChange?()
            let outcome = await settings.setDigestTime(hour: time.hour, minute: time.minute)
            nextTime = pendingState.queuedTime
            if nextTime == nil, outcome == .failed { pendingState.showError?() }
        }
        pendingState.time = nil
        pendingState.onChange?()
    }

    static func formatTime(_ time: DigestTime) -> String {
        String(format: "%02d:%02d", time.hour, time.minute)
    }

    /// An hour or a minute alone, as the time wheel shows it
    static func formatWheelValue(_ value: Int) -> String {
        String(format: "%02d", value)
    }

    static func title(of mode: AgentNewsNotificationSettings.Mode) -> String {
        switch mode {
        case .off: lang("$agent_digest_notifications_off")
        case .digest: lang("$agent_digest_notifications_daily")
        case .news: lang("$agent_digest_notifications_every")
        }
    }

    /// Only the digest's choice has a hint, which tells its time
    func hint(of mode: AgentNewsNotificationSettings.Mode) -> String? {
        switch mode {
        case .digest: L10n.agentDigestNotificationsDailyHint(time: Self.formatTime(digestTime))
        case .off, .news: nil
        }
    }

    struct DigestTime: Equatable {
        let hour: Int
        let minute: Int
    }

    @MainActor
    final class PendingState {
        static let shared = PendingState()

        var mode: AgentNewsNotificationSettings.Mode?
        var queuedMode: AgentNewsNotificationSettings.Mode?
        var time: DigestTime?
        var queuedTime: DigestTime?
        var isPermissionDenied = false
        weak var owner: AgentDigestSettingsModel?
        var onChange: (() -> Void)?
        var showError: (() -> Void)?
    }
}

/// The choice of MyPulse notifications and the digest's time in a bottom sheet as tall as its content, under the
/// header the app's sheets have, with Done at its foot. The time's row opens the system's time wheel under it, as a date
/// row in Settings does, with the hours and the quarter hours.
@MainActor
final class AgentDigestSettingsSheetVC: WViewController, UIPickerViewDataSource, UIPickerViewDelegate, UIScrollViewDelegate {
    private enum Metrics {
        static let sectionInset: CGFloat = 16
        static let rowInset: CGFloat = IOS_26_MODE_ENABLED ? 20 : 16
        static let textInset: CGFloat = sectionInset + rowInset
        // Done's capsule keeps the same distance from the sheet's sides and its foot, which the sheet's corners follow
        static let doneInset: CGFloat = IOS_26_MODE_ENABLED ? 30 : 16
        static let doneBottomInset: CGFloat = IOS_26_MODE_ENABLED ? 28 : 16
        static let pickerHeight: CGFloat = 180
        static let pickerComponentWidth: CGFloat = 64
    }

    private let model: AgentDigestSettingsModel
    private let navigationHeader = NavigationHeader2()
    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private let hourValueLabel = UILabel()
    private let enableButton = UIButton(type: .system)
    private let hourRow = UIStackView()
    private let hourControl = HourRowControl()
    private let hourPicker = UIPickerView()
    /// The line between the hour's row and its wheel, which shows with the wheel
    private let hourPickerSeparator = UIView()
    /// Clips the wheel, pinned at its top, as it opens and closes, so it stays in place while the rows under it move
    private let hourPickerContainer = UIView()
    private lazy var hourPickerContainerHeight = hourPickerContainer.heightAnchor.constraint(equalToConstant: 0)
    private var isHourPickerShown = false
    /// The content fits the sheet, which then neither scrolls nor stretches under the finger
    private var isContentFitting = true
    /// The tallest the sheet can be, as it last told its detent, which a sheet that ignores detents never tells
    private var maximumDetentValue: CGFloat?
    /// The content's height, which the sheet's one detent takes, up to the screen
    private var contentHeight: CGFloat?
    /// The sheet animates the wheel opening or closing, so a new height joins that animation instead of starting its own
    private var isAnimatingSheet = false
    private var modeRows: [AgentNewsNotificationSettings.Mode: ModeRow] = [:]
    private let permissionSection = UIStackView()
    private let doneButton = WButton(style: .primary)
    private let doneContainer = UIStackView()

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
        navigationHeader.setTitle(lang("Notifications"))
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

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        model.clearCallbacks()
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
        enableButton.setNeedsUpdateConfiguration()
        view.setNeedsLayout()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateDoneBottomInset()
        updateDetents()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        // The detent tells the sheet's tallest height for the new screen once it resolves again
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            self?.navigationController?.sheetPresentationController?.invalidateDetents()
            self?.view.setNeedsLayout()
        }
    }

    /// Done stands above the bottom safe area of a sheet at the screen's foot, and at its own distance from the foot of
    /// a sheet that floats over it
    private func updateDoneBottomInset() {
        let bottom = Metrics.doneBottomInset + (IOS_26_MODE_ENABLED ? 0 : view.safeAreaInsets.bottom)
        guard doneContainer.directionalLayoutMargins.bottom != bottom else { return }
        doneContainer.directionalLayoutMargins.bottom = bottom
    }

    /// As tall as the content under the header, up to the screen, where the content scrolls. The sheet adds its bottom
    /// safe area to the detent, and the content already ends with Done's distance from the foot.
    private func updateDetents() {
        guard let navigationController, let sheet = navigationController.sheetPresentationController else { return }
        // The header over the content and the bottom safe area under it, which the detent leaves out
        let chromeHeight = navigationController.navigationBar.frame.maxY - view.safeAreaInsets.bottom
        let height = stackView.systemLayoutSizeFitting(
            CGSize(width: view.bounds.width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height + chromeHeight
        isContentFitting = Self.isContentFitting(
            height: height,
            maximumDetentValue: maximumDetentValue,
            visibleHeight: isAnimatingSheet ? nil : scrollView.bounds.height + chromeHeight
        )
        updateScrolling()
        guard abs((contentHeight ?? 0) - height) > 0.5 else { return }
        let isFirstHeight = contentHeight == nil
        contentHeight = height
        preferredContentSize.height = height
        if isFirstHeight {
            // The detent reads the height as it resolves, so a new height only asks the sheet to resolve it again
            sheet.prefersScrollingExpandsWhenScrolledToEdge = false
            sheet.detents = [.custom(identifier: .init("agentDigestSettings")) { [weak self] context in
                if let self, self.maximumDetentValue != context.maximumDetentValue {
                    self.maximumDetentValue = context.maximumDetentValue
                    // The content fits the sheet's new tallest height or no longer does
                    self.view.setNeedsLayout()
                }
                return min(self?.contentHeight ?? context.maximumDetentValue, context.maximumDetentValue)
            }]
        } else if isAnimatingSheet || UIAccessibility.isReduceMotionEnabled {
            sheet.invalidateDetents()
        } else {
            sheet.animateChanges { sheet.invalidateDetents() }
        }
    }

    /// The content fits when it is no taller than the sheet can grow nor than what the sheet shows, and scrolls otherwise.
    /// While the sheet grows to a taller content, as with the hour's wheel opening, `visibleHeight` is nil, so the content
    /// stays in place instead of scrolling under the finger.
    static func isContentFitting(height: CGFloat, maximumDetentValue: CGFloat?, visibleHeight: CGFloat?) -> Bool {
        height <= min(maximumDetentValue ?? .infinity, visibleHeight ?? .infinity) + 0.5
    }

    private func updateScrolling() {
        scrollView.showsVerticalScrollIndicator = !isContentFitting
        if isContentFitting, scrollView.contentOffset.y > 0 {
            scrollView.contentOffset.y = 0
        }
    }

    /// A content that fits stays put under an upward drag; the scroll view still takes the drag, so the sheet doesn't
    /// stretch, and a downward one still pulls the sheet down
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard isContentFitting, scrollView.contentOffset.y > 0 else { return }
        scrollView.contentOffset.y = 0
    }

    private func update() {
        let timeText = AgentDigestSettingsModel.formatTime(model.digestTime)
        hourValueLabel.text = timeText
        hourControl.accessibilityValue = timeText
        // The wheel follows the time only when it changes elsewhere, so it never fights the finger turning it
        for (component, row) in pickerRows().enumerated() where hourPicker.selectedRow(inComponent: component) != row {
            hourPicker.selectRow(row, inComponent: component, animated: hourPicker.window != nil)
        }
        for (mode, row) in modeRows {
            row.configure(hint: model.hint(of: mode), isSelected: model.mode == mode)
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

    /// Opens or closes the hour's wheel under its row, the sheet growing or shrinking with it
    private func toggleHourPicker() {
        isHourPickerShown.toggle()
        hourControl.accessibilityTraits = isHourPickerShown ? [.button, .selected] : .button
        hourPicker.accessibilityElementsHidden = !isHourPickerShown
        let changes = {
            self.hourPickerContainerHeight.constant = self.isHourPickerShown ? Metrics.pickerHeight + 1 / UIScreen.main.scale : 0
            self.hourPicker.alpha = self.isHourPickerShown ? 1 : 0
            self.hourPickerSeparator.alpha = self.isHourPickerShown ? 1 : 0
            self.hourValueLabel.textColor = self.isHourPickerShown ? .tintColor : .air.secondaryLabel
            self.view.layoutIfNeeded()
            self.updateDetents()
        }
        guard !UIAccessibility.isReduceMotionEnabled else {
            changes()
            return
        }
        // The sheet's height and the rows move in one animation, the sheet's own
        if let sheet = navigationController?.sheetPresentationController {
            sheet.animateChanges {
                self.isAnimatingSheet = true
                changes()
                self.isAnimatingSheet = false
            }
        } else {
            UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState], animations: changes)
        }
    }

    // MARK: - The time's wheel: the hours, and the minutes in quarter hours

    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        2
    }

    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        Self.values(ofComponent: component).count
    }

    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        AgentDigestSettingsModel.formatWheelValue(Self.values(ofComponent: component)[row])
    }

    func pickerView(_ pickerView: UIPickerView, widthForComponent component: Int) -> CGFloat {
        Metrics.pickerComponentWidth
    }

    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        let value = Self.values(ofComponent: component)[row]
        if component == 0 {
            Task { await model.selectHour(value) }
        } else {
            Task { await model.selectMinute(value) }
        }
    }

    /// The wheel's row of the hour and of the minute, in the order of its components
    private func pickerRows() -> [Int] {
        [
            AgentDigestSettingsModel.hours.firstIndex(of: model.digestHour) ?? 0,
            AgentDigestSettingsModel.minutes.firstIndex(of: model.digestMinute) ?? 0,
        ]
    }

    private static func values(ofComponent component: Int) -> [Int] {
        component == 0 ? AgentDigestSettingsModel.hours : AgentDigestSettingsModel.minutes
    }

    private func configureViews() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.delegate = self
        // The content ends with Done's own distance from the sheet's foot
        scrollView.contentInsetAdjustmentBehavior = .never
        view.addSubview(scrollView)
        stackView.axis = .vertical
        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stackView)

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
        stackView.addArrangedSubview(inset(makeSection(rows), top: 16, bottom: 0, horizontal: 0))

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

        let hourTitle = makeLabel(lang("$agent_digest_time"), style: .body, color: .label)
        hourValueLabel.applyTextStyle(.body, scaling: .dynamic)
        hourValueLabel.textColor = .air.secondaryLabel
        hourValueLabel.setContentHuggingPriority(.required, for: .horizontal)
        hourValueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        hourRow.addArrangedSubview(hourTitle)
        hourRow.addArrangedSubview(hourValueLabel)
        hourRow.spacing = 8
        hourRow.isUserInteractionEnabled = false
        hourRow.isLayoutMarginsRelativeArrangement = true
        hourRow.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 11, leading: Metrics.rowInset, bottom: 11, trailing: Metrics.rowInset)
        hourRow.translatesAutoresizingMaskIntoConstraints = false
        hourControl.addSubview(hourRow)
        NSLayoutConstraint.activate([
            hourRow.topAnchor.constraint(equalTo: hourControl.topAnchor),
            hourRow.bottomAnchor.constraint(equalTo: hourControl.bottomAnchor),
            hourRow.leadingAnchor.constraint(equalTo: hourControl.leadingAnchor),
            hourRow.trailingAnchor.constraint(equalTo: hourControl.trailingAnchor),
            hourControl.heightAnchor.constraint(greaterThanOrEqualToConstant: S.sectionItemHeight),
        ])
        hourControl.isAccessibilityElement = true
        hourControl.accessibilityTraits = .button
        hourControl.accessibilityLabel = lang("$agent_digest_time")
        hourControl.accessibilityIdentifier = "AgentDigestHour"
        hourControl.addAction(UIAction { [weak self] _ in self?.toggleHourPicker() }, for: .touchUpInside)
        hourPicker.dataSource = self
        hourPicker.delegate = self
        hourPicker.alpha = 0
        hourPicker.accessibilityIdentifier = "AgentDigestHourPicker"
        hourPicker.accessibilityElementsHidden = true
        for (component, row) in pickerRows().enumerated() {
            hourPicker.selectRow(row, inComponent: component, animated: false)
        }
        hourPickerSeparator.backgroundColor = .air.separator
        hourPickerSeparator.alpha = 0
        hourPickerContainer.clipsToBounds = true
        for subview in [hourPickerSeparator, hourPicker] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            hourPickerContainer.addSubview(subview)
        }
        hourPickerContainerHeight.isActive = true
        NSLayoutConstraint.activate([
            hourPickerSeparator.topAnchor.constraint(equalTo: hourPickerContainer.topAnchor),
            hourPickerSeparator.leadingAnchor.constraint(equalTo: hourPickerContainer.leadingAnchor, constant: Metrics.rowInset),
            hourPickerSeparator.trailingAnchor.constraint(equalTo: hourPickerContainer.trailingAnchor),
            hourPickerSeparator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
            hourPicker.topAnchor.constraint(equalTo: hourPickerSeparator.bottomAnchor),
            hourPicker.leadingAnchor.constraint(equalTo: hourPickerContainer.leadingAnchor),
            hourPicker.trailingAnchor.constraint(equalTo: hourPickerContainer.trailingAnchor),
            hourPicker.heightAnchor.constraint(equalToConstant: Metrics.pickerHeight),
        ])
        let hourSection = makeSection([hourControl])
        (hourControl.superview as? UIStackView)?.addArrangedSubview(hourPickerContainer)
        stackView.addArrangedSubview(inset(hourSection, top: 24, bottom: 0, horizontal: 0))
        let hourHint = makeLabel(lang("$agent_digest_time_hint"), style: .footnote, color: .air.secondaryLabel)
        stackView.addArrangedSubview(inset(hourHint, top: 7, bottom: 0, horizontal: Metrics.textInset))

        doneButton.setTitle(lang("Done"), for: .normal)
        doneButton.accessibilityIdentifier = "AgentDigestDone"
        doneButton.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .touchUpInside)
        doneContainer.addArrangedSubview(doneButton)
        doneContainer.isLayoutMarginsRelativeArrangement = true
        doneContainer.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 24, leading: Metrics.doneInset, bottom: Metrics.doneBottomInset, trailing: Metrics.doneInset
        )
        stackView.addArrangedSubview(doneContainer)

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

/// A notification choice: its title, its hint if it has one, and the mark of the current choice, which moves to a choice
/// the moment it is tapped
private final class ModeRow: UIControl {
    private let titleLabel = UILabel()
    private let hintLabel = UILabel()
    private let markView = UIImageView(image: UIImage(systemName: "checkmark", withConfiguration: UIImage.SymbolConfiguration(textStyle: .body, scale: .medium)))

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
        markView.translatesAutoresizingMaskIntoConstraints = false
        mark.addSubview(markView)
        // The mark ends at the row's inset, where the hour's value ends, as Settings' checkmarks do
        NSLayoutConstraint.activate([
            markView.trailingAnchor.constraint(equalTo: mark.trailingAnchor),
            markView.centerYAnchor.constraint(equalTo: mark.centerYAnchor),
        ])
        let row = UIStackView(arrangedSubviews: [texts, mark])
        row.spacing = 12
        row.alignment = .center
        row.isUserInteractionEnabled = false
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            mark.widthAnchor.constraint(equalToConstant: 24),
            mark.heightAnchor.constraint(equalToConstant: 24),
            heightAnchor.constraint(greaterThanOrEqualToConstant: S.sectionItemHeight),
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

    func configure(hint: String?, isSelected: Bool) {
        hintLabel.text = hint
        hintLabel.isHidden = hint == nil
        markView.isHidden = !isSelected
        accessibilityLabel = [titleLabel.text, hint].compactMap { $0 }.joined(separator: ", ")
        accessibilityTraits = isSelected ? [.button, .selected] : .button
    }
}

/// The hour's row, which opens and closes the wheel under it and lights up while pressed, as a row of the app's lists
private final class HourRowControl: UIControl {
    override var isHighlighted: Bool {
        didSet { backgroundColor = isHighlighted ? .air.highlight : .clear }
    }
}
