import LottieKit
import UIKit

@MainActor
final class RootViewController: UIViewController {
    private enum RenderScaleOption: CaseIterable {
        case display
        case x1
        case x2
        case x3
        case x4
        case x6

        var shortTitle: String {
            switch self {
            case .display:
                return "Display"
            case .x1:
                return "1x"
            case .x2:
                return "2x"
            case .x3:
                return "3x"
            case .x4:
                return "4x"
            case .x6:
                return "6x"
            }
        }

        func scale(for screenScale: CGFloat) -> CGFloat {
            switch self {
            case .display:
                return screenScale
            case .x1:
                return 1.0
            case .x2:
                return 2.0
            case .x3:
                return 3.0
            case .x4:
                return 4.0
            case .x6:
                return 6.0
            }
        }

        func detailText(screenScale: CGFloat) -> String {
            switch self {
            case .display:
                return String(format: "display scale (%.2fx)", screenScale)
            case .x1:
                return "forced 1x"
            case .x2:
                return "forced 2x"
            case .x3:
                return "forced 3x"
            case .x4:
                return "forced 4x"
            case .x6:
                return "forced 6x"
            }
        }
    }

    private enum CacheMode: CaseIterable {
        case disabled
        case automatic
        case always

        var shortTitle: String {
            switch self {
            case .disabled:
                return "Off"
            case .automatic:
                return "Auto"
            case .always:
                return "On"
            }
        }

        var detailText: String {
            switch self {
            case .disabled:
                return "cache disabled"
            case .automatic:
                return "automatic for larger looping animations"
            case .always:
                return "always warm ARGB cache"
            }
        }

        var cachePolicy: LottieAnimationCachePolicy {
            switch self {
            case .disabled:
                return .disabled
            case .automatic:
                return .automatic
            case .always:
                return .always
            }
        }
    }

    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let stackView = UIStackView()
    private let backgroundGradientLayer = CAGradientLayer()

    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()

    private let stageView = UIView()
    private let stageGradientLayer = CAGradientLayer()
    private let animationView = LottieAnimationView()
    private let fpsBadgeLabel = InsetLabel()

    private let controlsStackView = UIStackView()
    private let topButtonsRow = UIStackView()
    private let bottomButtonsRow = UIStackView()
    private let scaleButton = UIButton(type: .system)
    private let cacheModeButton = UIButton(type: .system)
    private let clearCacheButton = UIButton(type: .system)
    private let playPauseButton = UIButton(type: .system)
    private let restartButton = UIButton(type: .system)
    private let scrubber = UISlider()
    private let noteLabel = UILabel()
    private let infoContainerView = UIView()
    private let infoLabel = UILabel()

    private var loadedAnimationInfo: LottieAnimationInfo?
    private var recentRenderTimestamps: [CFTimeInterval] = []
    private var statsTimer: Timer?
    private var isPlaying = true
    private var effectiveFPS: Double = 0.0
    private var selectedRenderScale: RenderScaleOption = .display
    private var selectedCacheMode: CacheMode = .disabled
    
    private static let byteCountFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }()

    override func viewDidLoad() {
        super.viewDidLoad()

        self.view.backgroundColor = .systemBackground
        self.configureBackground()
        self.configureLayout()
        self.configureButtons()
        self.rebuildRenderScaleMenu()
        self.rebuildCacheModeMenu()
        self.applySelectedRenderScale()
        self.applySelectedCacheMode()
        Task { [weak self] in
            guard let self else {
                return
            }
            await self.reloadAnimation(resetMetrics: true)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.installStatsTimerIfNeeded()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        self.statsTimer?.invalidate()
        self.statsTimer = nil
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        self.backgroundGradientLayer.frame = self.view.bounds
        self.stageGradientLayer.frame = self.stageView.bounds
        self.updateInfoLabel()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        self.updateGradientColors()
        self.rebuildRenderScaleMenu()
    }

    @objc private func playPausePressed() {
        self.isPlaying.toggle()
        if self.isPlaying {
            self.animationView.play()
        } else {
            self.animationView.pause()
        }
        self.updateButtonTitles()
        self.updateInfoLabel()
    }

    @objc private func restartPressed() {
        self.animationView.seek(to: 0.0)
        if self.isPlaying {
            self.animationView.play()
        }
    }

    @objc private func clearCachePressed() {
        let wasPlaying = self.isPlaying
        self.animationView.pause()
        Task { [weak self] in
            guard let self else {
                return
            }
            await LottieAnimationCache.clearAll()
            await self.reloadAnimation(resetMetrics: true)
            self.isPlaying = wasPlaying
            if self.isPlaying {
                self.animationView.play()
            } else {
                self.animationView.pause()
            }
            self.updateButtonTitles()
        }
    }

    @objc private func scrubberTouchDown() {
        self.animationView.pause()
    }

    @objc private func scrubberChanged() {
        self.animationView.seek(to: Double(self.scrubber.value))
    }

    @objc private func scrubberFinished() {
        if self.isPlaying {
            self.animationView.play()
        }
    }

    @objc private func statsTimerTick() {
        self.pruneRenderTimestamps(relativeTo: CACurrentMediaTime())
        self.updateEffectiveFPS()
        self.updateFPSBadge()
        self.updateInfoLabel()
    }

    private func configureBackground() {
        self.backgroundGradientLayer.startPoint = CGPoint(x: 0.0, y: 0.0)
        self.backgroundGradientLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
        self.view.layer.insertSublayer(self.backgroundGradientLayer, at: 0)
        self.updateGradientColors()
    }

    private func configureLayout() {
        self.scrollView.translatesAutoresizingMaskIntoConstraints = false
        self.scrollView.alwaysBounceVertical = true
        self.scrollView.contentInsetAdjustmentBehavior = .never

        self.contentView.translatesAutoresizingMaskIntoConstraints = false

        self.stackView.translatesAutoresizingMaskIntoConstraints = false
        self.stackView.axis = .vertical
        self.stackView.spacing = 14.0

        self.view.addSubview(self.scrollView)
        self.scrollView.addSubview(self.contentView)
        self.contentView.addSubview(self.stackView)

        NSLayoutConstraint.activate([
            self.scrollView.topAnchor.constraint(equalTo: self.view.topAnchor),
            self.scrollView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            self.scrollView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            self.scrollView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),

            self.contentView.topAnchor.constraint(equalTo: self.scrollView.contentLayoutGuide.topAnchor),
            self.contentView.leadingAnchor.constraint(equalTo: self.scrollView.contentLayoutGuide.leadingAnchor),
            self.contentView.trailingAnchor.constraint(equalTo: self.scrollView.contentLayoutGuide.trailingAnchor),
            self.contentView.bottomAnchor.constraint(equalTo: self.scrollView.contentLayoutGuide.bottomAnchor),
            self.contentView.widthAnchor.constraint(equalTo: self.scrollView.frameLayoutGuide.widthAnchor),

            self.stackView.topAnchor.constraint(equalTo: self.contentView.safeAreaLayoutGuide.topAnchor, constant: 14.0),
            self.stackView.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor),
            self.stackView.trailingAnchor.constraint(equalTo: self.contentView.trailingAnchor),
            self.stackView.bottomAnchor.constraint(equalTo: self.contentView.bottomAnchor, constant: -24.0),
        ])

        self.titleLabel.text = "Lottie Renderer"
        self.titleLabel.font = UIFont.systemFont(ofSize: 30.0, weight: .bold)
        self.titleLabel.textColor = .label

        self.subtitleLabel.text = "Compact harness for stress-testing RLottie render quality, cache behavior, and effective FPS."
        self.subtitleLabel.font = UIFont.preferredFont(forTextStyle: .subheadline)
        self.subtitleLabel.textColor = .secondaryLabel
        self.subtitleLabel.numberOfLines = 0

        self.stackView.addArrangedSubview(self.wrapInHorizontalInsetContainer(self.titleLabel))
        self.stackView.addArrangedSubview(self.wrapInHorizontalInsetContainer(self.subtitleLabel))

        self.stageView.translatesAutoresizingMaskIntoConstraints = false
        self.stageView.backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.72)
        self.stageView.layer.cornerRadius = 28.0
        self.stageView.layer.cornerCurve = .continuous
        self.stageView.layer.borderWidth = 1.0
        self.stageView.layer.borderColor = UIColor.separator.withAlphaComponent(0.14).cgColor
        self.stageView.clipsToBounds = true
        self.stageGradientLayer.startPoint = CGPoint(x: 0.0, y: 0.0)
        self.stageGradientLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
        self.stageView.layer.insertSublayer(self.stageGradientLayer, at: 0)

        self.animationView.translatesAutoresizingMaskIntoConstraints = false
        self.animationView.backgroundColor = .clear

        self.fpsBadgeLabel.translatesAutoresizingMaskIntoConstraints = false
        self.fpsBadgeLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 12.0, weight: .semibold)
        self.fpsBadgeLabel.textColor = .label
        self.fpsBadgeLabel.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.72)
        self.fpsBadgeLabel.layer.cornerRadius = 13.0
        self.fpsBadgeLabel.layer.cornerCurve = .continuous
        self.fpsBadgeLabel.layer.borderWidth = 1.0
        self.fpsBadgeLabel.layer.borderColor = UIColor.separator.withAlphaComponent(0.12).cgColor
        self.fpsBadgeLabel.clipsToBounds = true
        self.fpsBadgeLabel.contentInsets = UIEdgeInsets(top: 6.0, left: 10.0, bottom: 6.0, right: 10.0)
        self.fpsBadgeLabel.text = "0.0 fps"

        self.stageView.addSubview(self.animationView)
        self.stageView.addSubview(self.fpsBadgeLabel)
        self.stackView.addArrangedSubview(self.stageView)

        NSLayoutConstraint.activate([
            self.stageView.heightAnchor.constraint(equalTo: self.stageView.widthAnchor),

            self.animationView.topAnchor.constraint(equalTo: self.stageView.topAnchor),
            self.animationView.leadingAnchor.constraint(equalTo: self.stageView.leadingAnchor),
            self.animationView.trailingAnchor.constraint(equalTo: self.stageView.trailingAnchor),
            self.animationView.bottomAnchor.constraint(equalTo: self.stageView.bottomAnchor),

            self.fpsBadgeLabel.topAnchor.constraint(equalTo: self.stageView.topAnchor, constant: 12.0),
            self.fpsBadgeLabel.trailingAnchor.constraint(equalTo: self.stageView.trailingAnchor, constant: -12.0),
        ])

        self.animationView.onAnimationLoaded = { [weak self] info in
            self?.loadedAnimationInfo = info
            self?.updateInfoLabel()
        }
        self.animationView.onFrameRendered = { [weak self] event in
            self?.recordRenderEvent(event)
        }
        self.animationView.onPreparationUpdated = { [weak self] _ in
            self?.updateInfoLabel()
        }
        self.animationView.onPlaybackBackendChanged = { [weak self] _ in
            self?.updateFPSBadge()
            self?.updateInfoLabel()
        }

        self.controlsStackView.axis = .vertical
        self.controlsStackView.spacing = 10.0

        self.topButtonsRow.axis = .horizontal
        self.topButtonsRow.spacing = 10.0
        self.topButtonsRow.distribution = .fillEqually

        self.bottomButtonsRow.axis = .horizontal
        self.bottomButtonsRow.spacing = 10.0
        self.bottomButtonsRow.distribution = .fillEqually

        self.topButtonsRow.addArrangedSubview(self.scaleButton)
        self.topButtonsRow.addArrangedSubview(self.cacheModeButton)
        self.topButtonsRow.addArrangedSubview(self.clearCacheButton)
        self.bottomButtonsRow.addArrangedSubview(self.playPauseButton)
        self.bottomButtonsRow.addArrangedSubview(self.restartButton)

        self.scrubber.minimumValue = 0.0
        self.scrubber.maximumValue = 1.0
        self.scrubber.minimumTrackTintColor = .tintColor
        self.scrubber.maximumTrackTintColor = UIColor.tertiaryLabel.withAlphaComponent(0.24)
        self.scrubber.addTarget(self, action: #selector(self.scrubberTouchDown), for: .touchDown)
        self.scrubber.addTarget(self, action: #selector(self.scrubberChanged), for: .valueChanged)
        self.scrubber.addTarget(self, action: #selector(self.scrubberFinished), for: [.touchUpInside, .touchUpOutside, .touchCancel])

        self.noteLabel.font = UIFont.preferredFont(forTextStyle: .footnote)
        self.noteLabel.textColor = .secondaryLabel
        self.noteLabel.numberOfLines = 0
        self.noteLabel.text = "Off disables cache, Auto caches larger looping animations, and On always warms the ARGB cache in the background."

        self.infoContainerView.backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.72)
        self.infoContainerView.layer.cornerRadius = 18.0
        self.infoContainerView.layer.cornerCurve = .continuous

        self.infoLabel.translatesAutoresizingMaskIntoConstraints = false
        self.infoLabel.font = UIFont.monospacedSystemFont(ofSize: 12.5, weight: .medium)
        self.infoLabel.textColor = .secondaryLabel
        self.infoLabel.numberOfLines = 0

        self.infoContainerView.addSubview(self.infoLabel)
        NSLayoutConstraint.activate([
            self.infoLabel.topAnchor.constraint(equalTo: self.infoContainerView.topAnchor, constant: 14.0),
            self.infoLabel.leadingAnchor.constraint(equalTo: self.infoContainerView.leadingAnchor, constant: 14.0),
            self.infoLabel.trailingAnchor.constraint(equalTo: self.infoContainerView.trailingAnchor, constant: -14.0),
            self.infoLabel.bottomAnchor.constraint(equalTo: self.infoContainerView.bottomAnchor, constant: -14.0),
        ])

        self.controlsStackView.addArrangedSubview(self.topButtonsRow)
        self.controlsStackView.addArrangedSubview(self.scrubber)
        self.controlsStackView.addArrangedSubview(self.bottomButtonsRow)
        self.controlsStackView.addArrangedSubview(self.noteLabel)

        self.stackView.addArrangedSubview(self.wrapInHorizontalInsetContainer(self.controlsStackView))
        self.stackView.addArrangedSubview(self.wrapInHorizontalInsetContainer(self.infoContainerView))
    }

    private func configureButtons() {
        self.configureMenuButton(
            self.scaleButton,
            title: "Scale",
            imageName: "arrow.up.left.and.arrow.down.right"
        )
        self.scaleButton.showsMenuAsPrimaryAction = true

        self.configureMenuButton(
            self.cacheModeButton,
            title: "Mode",
            imageName: "square.stack.3d.down.right"
        )
        self.cacheModeButton.showsMenuAsPrimaryAction = true

        var clearConfig = UIButton.Configuration.gray()
        clearConfig.cornerStyle = .large
        clearConfig.baseForegroundColor = .systemRed
        clearConfig.image = UIImage(systemName: "trash")
        clearConfig.imagePadding = 6.0
        clearConfig.title = "Clear Cache"
        self.clearCacheButton.configuration = clearConfig
        self.clearCacheButton.addTarget(self, action: #selector(self.clearCachePressed), for: .touchUpInside)

        var playConfig = UIButton.Configuration.tinted()
        playConfig.cornerStyle = .large
        playConfig.imagePadding = 6.0
        self.playPauseButton.configuration = playConfig
        self.playPauseButton.addTarget(self, action: #selector(self.playPausePressed), for: .touchUpInside)

        var restartConfig = UIButton.Configuration.gray()
        restartConfig.cornerStyle = .large
        restartConfig.image = UIImage(systemName: "arrow.counterclockwise")
        restartConfig.imagePadding = 6.0
        restartConfig.title = "Restart"
        self.restartButton.configuration = restartConfig
        self.restartButton.addTarget(self, action: #selector(self.restartPressed), for: .touchUpInside)

        self.updateButtonTitles()
    }

    private func configureMenuButton(_ button: UIButton, title: String, imageName: String) {
        var configuration = UIButton.Configuration.gray()
        configuration.cornerStyle = .large
        configuration.image = UIImage(systemName: imageName)
        configuration.imagePadding = 6.0
        configuration.title = title
        button.configuration = configuration
    }

    private func rebuildRenderScaleMenu() {
        let screenScale = self.view.window?.screen.scale ?? UIScreen.main.scale
        let actions = RenderScaleOption.allCases.map { option in
            UIAction(
                title: option.detailText(screenScale: screenScale),
                state: option == self.selectedRenderScale ? .on : .off
            ) { [weak self] _ in
                guard let self else {
                    return
                }
                self.selectedRenderScale = option
                self.applySelectedRenderScale()
                self.rebuildRenderScaleMenu()
                self.updateButtonTitles()
                self.updateInfoLabel()
            }
        }
        self.scaleButton.menu = UIMenu(title: "Render Scale", children: actions)
    }

    private func rebuildCacheModeMenu() {
        let actions = CacheMode.allCases.map { mode in
            UIAction(
                title: mode.detailText,
                state: mode == self.selectedCacheMode ? .on : .off
            ) { [weak self] _ in
                guard let self else {
                    return
                }
                self.selectedCacheMode = mode
                self.applySelectedCacheMode()
                self.rebuildCacheModeMenu()
                self.updateButtonTitles()
                self.updateInfoLabel()
            }
        }
        self.cacheModeButton.menu = UIMenu(title: "Cache Mode", children: actions)
    }

    private func installStatsTimerIfNeeded() {
        guard self.statsTimer == nil else {
            return
        }
        let timer = Timer(timeInterval: 0.25, target: self, selector: #selector(self.statsTimerTick), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        self.statsTimer = timer
    }

    private func updateGradientColors() {
        let topColor = UIColor { traits in
            if traits.userInterfaceStyle == .dark {
                return UIColor(red: 0.07, green: 0.09, blue: 0.14, alpha: 1.0)
            } else {
                return UIColor(red: 0.96, green: 0.97, blue: 0.99, alpha: 1.0)
            }
        }
        let bottomColor = UIColor.systemBackground
        let stageTopColor = UIColor { traits in
            if traits.userInterfaceStyle == .dark {
                return UIColor(red: 0.17, green: 0.21, blue: 0.30, alpha: 0.96)
            } else {
                return UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.98)
            }
        }
        let stageBottomColor = UIColor { traits in
            if traits.userInterfaceStyle == .dark {
                return UIColor(red: 0.11, green: 0.13, blue: 0.20, alpha: 0.96)
            } else {
                return UIColor(red: 0.90, green: 0.94, blue: 0.99, alpha: 0.96)
            }
        }

        self.backgroundGradientLayer.colors = [
            topColor.resolvedColor(with: self.traitCollection).cgColor,
            bottomColor.resolvedColor(with: self.traitCollection).cgColor,
        ]
        self.stageGradientLayer.colors = [
            stageTopColor.resolvedColor(with: self.traitCollection).cgColor,
            stageBottomColor.resolvedColor(with: self.traitCollection).cgColor,
        ]
    }

    private func reloadAnimation(resetMetrics: Bool) async {
        if resetMetrics {
            self.loadedAnimationInfo = nil
            self.recentRenderTimestamps.removeAll()
            self.effectiveFPS = 0.0
            self.scrubber.value = 0.0
            self.updateFPSBadge()
        }

        guard let path = Bundle.main.path(forResource: "trapped_heart.lottie", ofType: "json") else {
            self.infoLabel.text = "Missing demo asset: trapped_heart.lottie.json"
            return
        }

        do {
            try await self.animationView.setAnimation(
                source: LottieAnimationSource.file(path: path),
                playbackMode: .loop
            )
            if !self.isPlaying {
                self.animationView.pause()
            }
            self.updateInfoLabel()
        } catch is CancellationError {
            return
        } catch {
            self.infoLabel.text = "Failed to load animation: \(error)"
        }
    }

    private func applySelectedRenderScale() {
        let screenScale = self.view.window?.screen.scale ?? UIScreen.main.scale
        self.animationView.renderingScale = self.selectedRenderScale.scale(for: screenScale)
    }

    private func applySelectedCacheMode() {
        self.animationView.cachePolicy = self.selectedCacheMode.cachePolicy
    }

    private func recordRenderEvent(_ event: LottieAnimationRenderEvent) {
        self.recentRenderTimestamps.append(event.timestamp)
        self.pruneRenderTimestamps(relativeTo: event.timestamp)
        self.updateEffectiveFPS()
        self.updateFPSBadge()
        self.updateInfoLabel()
    }

    private func pruneRenderTimestamps(relativeTo timestamp: CFTimeInterval) {
        let lowerBound = timestamp - 1.0
        while let first = self.recentRenderTimestamps.first, first < lowerBound {
            self.recentRenderTimestamps.removeFirst()
        }
    }

    private func updateEffectiveFPS() {
        guard
            let first = self.recentRenderTimestamps.first,
            let last = self.recentRenderTimestamps.last,
            self.recentRenderTimestamps.count >= 2,
            last > first
        else {
            self.effectiveFPS = 0.0
            return
        }
        self.effectiveFPS = Double(self.recentRenderTimestamps.count - 1) / (last - first)
    }

    private func updateFPSBadge() {
        self.fpsBadgeLabel.text = String(
            format: "%.1f fps · %@",
            self.effectiveFPS,
            self.animationView.currentPlaybackBackend.rawValue
        )
    }

    private func updateButtonTitles() {
        self.scaleButton.configuration?.title = "Scale: \(self.selectedRenderScale.shortTitle)"
        self.cacheModeButton.configuration?.title = "Mode: \(self.selectedCacheMode.shortTitle)"
        self.playPauseButton.configuration?.title = self.isPlaying ? "Pause" : "Play"
        self.playPauseButton.configuration?.image = UIImage(systemName: self.isPlaying ? "pause.fill" : "play.fill")
    }

    private func updateInfoLabel() {
        guard let info = self.loadedAnimationInfo else {
            return
        }

        let screenScale = self.view.window?.screen.scale ?? UIScreen.main.scale
        let renderSize = self.animationView.currentRenderPixelSize
        let playbackText = self.isPlaying ? "playing" : "paused"
        let preparationStateText = self.animationView.isPreparingPlaybackMetrics ? "preparing" : "ready"
        let backendText = self.animationView.currentPlaybackBackend.rawValue
        let cacheModeText = self.selectedCacheMode.detailText
        let preparationDurationText: String
        if let duration = self.animationView.lastPreparationDuration {
            preparationDurationText = String(format: "%.2fs", duration)
        } else {
            preparationDurationText = "n/a"
        }
        let cacheSizeText = Self.byteCountFormatter.string(fromByteCount: self.animationView.currentCacheSizeBytes)

        self.infoLabel.text = String(
            format: """
            asset         trapped_heart.lottie.json
            source        %.0fx%.0f px
            render        %.0fx%.0f px
            scale         %@
            cache mode    %@
            nominal fps   %d
            effective fps %.1f
            backend       %@
            duration      %.2fs
            state         %@
            prep          %@
            prep time     %@
            cache         %@
            """,
            info.dimensions.width,
            info.dimensions.height,
            renderSize.width,
            renderSize.height,
            self.selectedRenderScale.detailText(screenScale: screenScale),
            cacheModeText,
            info.frameRate,
            self.effectiveFPS,
            backendText,
            info.duration,
            playbackText,
            preparationStateText,
            preparationDurationText,
            cacheSizeText
        )
    }

    private func wrapInHorizontalInsetContainer(_ view: UIView, inset: CGFloat = 16.0) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: inset),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -inset),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }
}

private final class InsetLabel: UILabel {
    var contentInsets: UIEdgeInsets = .zero {
        didSet {
            self.invalidateIntrinsicContentSize()
        }
    }

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: self.contentInsets))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(
            width: size.width + self.contentInsets.left + self.contentInsets.right,
            height: size.height + self.contentInsets.top + self.contentInsets.bottom
        )
    }
}
