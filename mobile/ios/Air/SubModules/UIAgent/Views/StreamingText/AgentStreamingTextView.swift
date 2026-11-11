import UIKit
import UIComponents

private enum AgentStreamingTextMetrics {
    static let minimumLayoutWidth: CGFloat = 120
    static let minimumVisibleHeight: CGFloat = 20
    static let bubbleMaxWidthMultiplier: CGFloat = 0.8
    static let bubbleBodyHorizontalPadding: CGFloat = 14

    static let revealDurationMultiplier: Double = 1.0
    static let heightSmoothingTau: TimeInterval = 0.14
    static let heightSmoothingFrameDtCap: TimeInterval = 0.05
    static let heightSettleThreshold: CGFloat = 0.5
    static let widthLeadSmoothingTau: TimeInterval = 0.4
    /// Streaming text is laid out at most this often, however fast its chunks arrive
    static let streamingLayoutInterval: CFTimeInterval = 0.1
    /// Glyphs revealed beyond this many animating ones, as when a burst of chunks catches up, show without animating
    static let maximumAnimatingSnippetCount = 150
}

private final class AgentRevealSnippetLayer: CALayer {
    let characterIndex: Int
    let restingFrame: CGRect
    var isFinished = false

    init(characterIndex: Int, restingFrame: CGRect) {
        self.characterIndex = characterIndex
        self.restingFrame = restingFrame
        super.init()
    }

    override init(layer: Any) {
        let other = layer as? AgentRevealSnippetLayer
        self.characterIndex = other?.characterIndex ?? 0
        self.restingFrame = other?.restingFrame ?? .zero
        super.init(layer: layer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// How a streamed character comes in, as the transcript's characters do: out of a blur and transparent, sharp within
/// `sharpenDuration`, in the Agent's colours that then turn into the text's own colours within `colorDuration`. It
/// arrives in the Agent's blue, which turns violet on its way to the text's colours, so the fresh end of a line runs
/// from blue to violet as the thinking glow does. With Reduce Motion it only fades in.
@MainActor
enum AgentStreamedCharacterAppearance {
    static let sharpenDuration = AgentDictationTextReveal.sharpenDuration
    static let colorDuration = AgentDictationTextReveal.colorDuration
    static let initialOpacity: Float = 0.15
    static let initialGlowOpacity: Float = 0.9
    static let initialGlowRadius: CGFloat = 3

    /// How long a character takes to settle in its final colours
    static func getDuration(isMotionReduced: Bool) -> TimeInterval {
        isMotionReduced ? sharpenDuration : sharpenDuration + colorDuration
    }

    /// A character's opacity, its glow's opacity, and how much of the Agent's colours, `accent`, it still shows over its
    /// own colour
    struct Appearance {
        let opacity: Float
        let glowOpacity: Float
        let accent: Float
    }

    /// The character `age` seconds after it arrived
    static func getAppearance(age: TimeInterval) -> Appearance {
        let sharpness = Float(min(1, max(0, age / sharpenDuration)))
        let toText = Float(min(1, max(0, (age - sharpenDuration) / colorDuration)))
        let opacity = initialOpacity + (1 - initialOpacity) * sharpness
        return Appearance(
            opacity: opacity,
            glowOpacity: initialGlowOpacity * (1 - sharpness),
            accent: opacity * (1 - toText)
        )
    }

    /// How far the Agent's colours over the character have turned from blue to violet, `age` seconds after it arrived:
    /// blue while it sharpens, violet by the middle of its turn into its own colour
    static func getViolet(age: TimeInterval) -> Float {
        let progress = Float(min(1, max(0, (age - sharpenDuration) / (colorDuration / 2))))
        return progress * progress * (3 - 2 * progress)
    }

    /// The opacities of the character's copy in the Agent's blue and of its copy in the violet over it, which together
    /// show `accent` of the Agent's colours over the character's own
    static func getTintOpacities(age: TimeInterval) -> (blue: Float, violet: Float) {
        let accent = getAppearance(age: age).accent
        let violet = accent * getViolet(age: age)
        let blue = violet < 1 ? (accent - violet) / (1 - violet) : 0
        return (blue, violet)
    }

    /// The key times of a character's settling and its blue and violet copies' opacities at them
    struct TintKeyframes {
        let keyTimes: [NSNumber]
        let blue: [NSNumber]
        let violet: [NSNumber]
    }

    /// `getTintOpacities` over a character's settling, sampled every 25 ms, as keyframes
    static let tintKeyframes: TintKeyframes = {
        let total = AgentStreamedCharacterAppearance.sharpenDuration + AgentStreamedCharacterAppearance.colorDuration
        let steps = Int((total / 0.025).rounded())
        let ages = (0...steps).map { total * Double($0) / Double(steps) }
        let opacities = ages.map { AgentStreamedCharacterAppearance.getTintOpacities(age: $0) }
        return TintKeyframes(
            keyTimes: ages.map { NSNumber(value: $0 / total) },
            blue: opacities.map { NSNumber(value: $0.blue) },
            violet: opacities.map { NSNumber(value: $0.violet) }
        )
    }()
}

@MainActor
final class AgentStreamingTextView: UIView {
    var onPreferredHeightChanged: ((_ animated: Bool) -> Void)?
    var onRevealCompleted: (() -> Void)?
    var onURLTap: ((URL) -> Void)?
    private var linkMenu: AgentLinkMenu?

    override var isHidden: Bool {
        didSet {
            // A table or semantic answer replaces this view; discard sizing left by the previous text.
            if isHidden && !oldValue {
                hardResetForReuse()
            }
        }
    }

    private let renderContainer = UIView()
    private let renderImageView = UIImageView()
    private let revealMaskLayer = CAShapeLayer()
    private var animatingSnippetLayers: [AgentRevealSnippetLayer] = []
    /// The Agent's blue and violet over the characters still turning into their own colours, the violet over the blue:
    /// a layer of each, masked by a copy of each of those characters and sized to just them, so a long answer animates
    /// only its last few lines
    private let blueAccentLayer = CALayer()
    private let violetAccentLayer = CALayer()
    private var accentLayers: [CALayer] { [blueAccentLayer, violetAccentLayer] }
    private var accentCharacterLayers: [AgentRevealSnippetLayer] = []

    private var layout: AgentStreamingTextLayout?
    private var revealController: AgentTextRevealController?
    private var displayLinkSubscriptionID: UUID?
    private var revealCharacterCount: Int?
    private var previousRevealCharacterCount = 0
    private var isDrainingSnippets = false
    private var allowsLinkInteraction = false
    private var layoutMaxWidth: CGFloat = 0
    private var isInStreamingMode = false
    private var finalizedAllowsLinks = false

    private var pendingConfiguration: PendingConfiguration?
    private var revealedWidthConstraint: NSLayoutConstraint?
    private var revealedHeightConstraint: NSLayoutConstraint?
    private var renderContainerWidthConstraint: NSLayoutConstraint?
    private var renderContainerHeightConstraint: NSLayoutConstraint?
    private var lastReportedSize: CGSize = .zero

    private var displayedVisibleHeight: CGFloat = AgentStreamingTextMetrics.minimumVisibleHeight
    private var pendingTargetHeight: CGFloat = AgentStreamingTextMetrics.minimumVisibleHeight
    private var lastHeightSmoothingTime: Double?
    private var displayedVisibleWidth: CGFloat = 1
    private var lastWidthSmoothingTime: Double?
    private var pendingTargetWidth: CGFloat = 1
    private var appliedVisibleWidth: CGFloat = 1
    private var lastSnippetSpawnTime: CFTimeInterval = 0
    private var hasFinishedSnippets = false
    private var isFinishedSnippetRemovalScheduled = false
    private var streamingLayoutGeneration = 0
    private var isStreamingLayoutPending = false
    private var lastStreamingLayoutStartTime: CFTimeInterval = 0

    private func pointInRenderContainer(_ point: CGPoint) -> CGPoint {
        renderContainer.convert(point, from: self)
    }

    private struct PendingConfiguration: Equatable {
        let text: String
        let textColor: UIColor
        let isStreaming: Bool
        let hadStreaming: Bool
        let rendersMarkdown: Bool
        let markdownProfile: AgentMessageMarkdownProfile
        let baseFont: UIFont
        let allowsLinks: Bool
    }

    private var appliedConfiguration: PendingConfiguration?
    private var appliedLayoutMaxWidth: CGFloat = 0
    private var appliedUserInterfaceStyle: UIUserInterfaceStyle = .unspecified
    private var streamingIdentity: String?
    private var isSoftReusePending = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let id = displayLinkSubscriptionID {
            DispatchQueue.main.async {
                AgentDisplayLinkDriver.shared.remove(id)
            }
        }
    }

    var displayText: String {
        layout?.attributedString.string ?? pendingConfiguration?.text ?? ""
    }

    /// The displayed text with each link's URL after its label
    var copyText: String {
        layout.map { AgentTextLinks.copyText(from: $0.attributedString) } ?? displayText
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) else { return }
        updateTextColors()
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        updateTextColors()
    }

    private func updateTextColors() {
        guard let configuration = appliedConfiguration ?? pendingConfiguration else { return }
        pendingConfiguration = configuration
        appliedConfiguration = nil
        // A layout in progress still has the old colors
        cancelStreamingLayout()
        applyPendingConfigurationIfPossible()
    }

    override var intrinsicContentSize: CGSize {
        guard let layout else {
            return CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric)
        }
        guard isInStreamingMode else {
            return CGSize(
                width: max(layout.fullSize.width, 1),
                height: max(layout.fullSize.height, AgentStreamingTextMetrics.minimumVisibleHeight)
            )
        }
        return CGSize(
            width: max(appliedVisibleWidth, 1),
            height: max(displayedVisibleHeight, AgentStreamingTextMetrics.minimumVisibleHeight)
        )
    }

    func prepareForReuse() {
        isSoftReusePending = true
        if isStreamingLayoutPending {
            // The same message may come back to this view, and its text must be laid out again then
            cancelStreamingLayout()
            appliedConfiguration = nil
        }
        stopRevealAnimation(resetController: false)
        onPreferredHeightChanged = nil
        onRevealCompleted = nil
        onURLTap = nil
    }

    /// Drops the text revealed so far and keeps the callbacks, so the next text reveals as one of its own: an answer's
    /// first lines have moved into the blocks above this view
    func startOver() {
        hardResetForReuse()
    }

    private func hardResetForReuse() {
        cancelStreamingLayout()
        stopRevealAnimation(resetController: true)
        removeAllSnippets()
        layout = nil
        pendingConfiguration = nil
        appliedConfiguration = nil
        appliedLayoutMaxWidth = 0
        appliedUserInterfaceStyle = .unspecified
        streamingIdentity = nil
        revealCharacterCount = nil
        previousRevealCharacterCount = 0
        isDrainingSnippets = false
        allowsLinkInteraction = false
        isInStreamingMode = false
        finalizedAllowsLinks = false
        layoutMaxWidth = 0
        renderImageView.image = nil
        detachRevealMask()
        lastReportedSize = .zero
        revealedWidthConstraint?.isActive = false
        revealedHeightConstraint?.isActive = false
        revealedWidthConstraint?.constant = 1
        revealedHeightConstraint?.constant = AgentStreamingTextMetrics.minimumVisibleHeight
        renderContainerWidthConstraint?.constant = 1
        renderContainerHeightConstraint?.constant = 1
        displayedVisibleHeight = AgentStreamingTextMetrics.minimumVisibleHeight
        pendingTargetHeight = AgentStreamingTextMetrics.minimumVisibleHeight
        lastHeightSmoothingTime = nil
        displayedVisibleWidth = 1
        lastWidthSmoothingTime = nil
        pendingTargetWidth = 1
        appliedVisibleWidth = 1
        lastSnippetSpawnTime = 0
        invalidateIntrinsicContentSize()
    }

    func configure(
        text: String,
        textColor: UIColor,
        isStreaming: Bool,
        hadStreaming: Bool,
        rendersMarkdown: Bool,
        markdownProfile: AgentMessageMarkdownProfile = .legacy,
        baseFont: UIFont = AgentMessageTextRenderer.baseFont,
        allowsLinks: Bool,
        layoutMaxWidth: CGFloat,
        streamingIdentity: String? = nil
    ) {
        if isSoftReusePending {
            isSoftReusePending = false
            let sameStreamingIdentity = streamingIdentity != nil
                && streamingIdentity == self.streamingIdentity
                && (isStreaming || hadStreaming)
            if !sameStreamingIdentity {
                hardResetForReuse()
            }
        }

        self.streamingIdentity = streamingIdentity
        pendingConfiguration = PendingConfiguration(
            text: text,
            textColor: textColor,
            isStreaming: isStreaming,
            hadStreaming: hadStreaming,
            rendersMarkdown: rendersMarkdown,
            markdownProfile: markdownProfile,
            baseFont: baseFont,
            allowsLinks: allowsLinks
        )
        self.layoutMaxWidth = max(AgentStreamingTextMetrics.minimumLayoutWidth, layoutMaxWidth)
        applyPendingConfigurationIfPossible()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let resolvedWidth = resolvedLayoutMaxWidth()
        guard resolvedWidth >= AgentStreamingTextMetrics.minimumLayoutWidth else { return }
        guard resolvedWidth > layoutMaxWidth + 0.5 else { return }

        layoutMaxWidth = resolvedWidth
        if pendingConfiguration != nil || layout != nil {
            applyPendingConfigurationIfPossible()
        }
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard allowsLinkInteraction,
              layout?.link(at: pointInRenderContainer(point)) != nil else { return false }
        return bounds.contains(point)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        guard allowsLinkInteraction,
              let touch = touches.first,
              let url = layout?.link(at: pointInRenderContainer(touch.location(in: self))) else {
            return
        }
        onURLTap?(url)
    }

    private func setupViews() {
        linkMenu = AgentLinkMenu(source: self, linkAt: { [weak self] point in
            guard let self, self.allowsLinkInteraction else { return nil }
            return self.layout?.link(at: self.pointInRenderContainer(point))
        }, open: { [weak self] url in self?.onURLTap?(url) })
        backgroundColor = .clear
        clipsToBounds = false

        renderContainer.backgroundColor = .clear
        renderContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(renderContainer)

        renderImageView.contentMode = .topLeft
        renderImageView.translatesAutoresizingMaskIntoConstraints = false
        renderContainer.addSubview(renderImageView)
        for accentLayer in accentLayers {
            accentLayer.mask = CALayer()
            accentLayer.isHidden = true
            renderContainer.layer.addSublayer(accentLayer)
        }

        revealMaskLayer.fillColor = UIColor.white.cgColor

        let widthConstraint = widthAnchor.constraint(equalToConstant: 1)
        widthConstraint.priority = UILayoutPriority(999)
        let heightConstraint = heightAnchor.constraint(equalToConstant: AgentStreamingTextMetrics.minimumVisibleHeight)
        heightConstraint.priority = UILayoutPriority(999)
        revealedWidthConstraint = widthConstraint
        revealedHeightConstraint = heightConstraint

        renderContainerWidthConstraint = renderContainer.widthAnchor.constraint(equalToConstant: 1)
        renderContainerHeightConstraint = renderContainer.heightAnchor.constraint(equalToConstant: 1)
        NSLayoutConstraint.activate([
            renderContainer.topAnchor.constraint(equalTo: topAnchor),
            renderContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            renderContainerWidthConstraint!,
            renderContainerHeightConstraint!,

            renderImageView.topAnchor.constraint(equalTo: renderContainer.topAnchor),
            renderImageView.leadingAnchor.constraint(equalTo: renderContainer.leadingAnchor),
            renderImageView.trailingAnchor.constraint(equalTo: renderContainer.trailingAnchor),
            renderImageView.bottomAnchor.constraint(equalTo: renderContainer.bottomAnchor)
        ])

        setContentCompressionResistancePriority(.defaultHigh, for: .vertical)
        setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
        setContentHuggingPriority(.defaultHigh, for: .horizontal)
    }

    private func resolvedLayoutMaxWidth() -> CGFloat {
        if layoutMaxWidth >= AgentStreamingTextMetrics.minimumLayoutWidth {
            return layoutMaxWidth
        }
        let candidateWidth = max(
            bounds.width,
            superview?.bounds.width ?? 0,
            (superview?.superview?.bounds.width ?? 0) * AgentStreamingTextMetrics.bubbleMaxWidthMultiplier
        )
        if candidateWidth >= AgentStreamingTextMetrics.minimumLayoutWidth {
            return candidateWidth - AgentStreamingTextMetrics.bubbleBodyHorizontalPadding * 2
        }
        return max(layoutMaxWidth, AgentStreamingTextMetrics.minimumLayoutWidth)
    }

    private func applyPendingConfigurationIfPossible() {
        guard let configuration = pendingConfiguration else { return }
        guard layoutMaxWidth >= AgentStreamingTextMetrics.minimumLayoutWidth else { return }

        if configuration == appliedConfiguration,
           abs(layoutMaxWidth - appliedLayoutMaxWidth) < 0.5,
           appliedUserInterfaceStyle == traitCollection.userInterfaceStyle,
           layout != nil {
            if configuration.isStreaming || (configuration.hadStreaming && (isInStreamingMode || revealController != nil)) {
                updateRevealAnimation(
                    hasStreaming: configuration.isStreaming,
                    hadStreaming: configuration.hadStreaming
                )
            }
            return
        }
        appliedConfiguration = configuration
        appliedLayoutMaxWidth = layoutMaxWidth
        appliedUserInterfaceStyle = traitCollection.userInterfaceStyle

        if configuration.isStreaming {
            isInStreamingMode = true
            allowsLinkInteraction = false
            guard layout != nil else {
                applyStreamingLayout(AgentStreamingTextLayout.make(
                    attributedString: makeAttributedText(for: configuration),
                    maxWidth: layoutMaxWidth
                ))
                return
            }
            scheduleStreamingLayout()
            return
        }

        cancelStreamingLayout()
        // Answer links are styled from their first glyph and become tappable once the answer is revealed
        let allowsLinks = configuration.allowsLinks || AgentTextLinks.containsLinks(configuration.text)
        allowsLinkInteraction = allowsLinks && !isInStreamingMode

        if configuration.hadStreaming, isInStreamingMode {
            finalizedAllowsLinks = allowsLinks
            applyLayout(
                AgentStreamingTextLayout.make(attributedString: makeAttributedText(for: configuration), maxWidth: layoutMaxWidth),
                keepingReveal: true
            )
            updateRevealAnimation(hasStreaming: false, hadStreaming: true)
            return
        }

        isInStreamingMode = false
        isDrainingSnippets = false
        stopRevealAnimation(resetController: true)
        removeAllSnippets()
        let textColor = configuration.textColor.resolvedColor(with: traitCollection)
        let linkColor = tintColor.resolvedColor(with: traitCollection)
        let key = AgentTextLayoutCache.Key(
            text: configuration.text,
            textColor: textColor,
            linkColor: linkColor,
            font: configuration.baseFont,
            rendersMarkdown: configuration.rendersMarkdown,
            markdownProfile: configuration.markdownProfile,
            detectsLinks: configuration.allowsLinks,
            maxWidth: layoutMaxWidth
        )
        let staticLayout = AgentTextLayoutCache.shared.getLayout(for: key) {
            AgentStreamingTextLayout.make(
                attributedString: makeAttributedText(for: configuration),
                maxWidth: layoutMaxWidth,
                measuresCharacters: false
            )
        }
        applyLayout(staticLayout, keepingReveal: false)
        allowsLinkInteraction = allowsLinks
    }

    private func makeAttributedText(for configuration: PendingConfiguration) -> NSAttributedString {
        AgentMessageTextRenderer.makeAttributedText(
            configuration.text,
            textColor: configuration.textColor.resolvedColor(with: traitCollection),
            rendersMarkdown: configuration.rendersMarkdown,
            detectsLinks: configuration.allowsLinks,
            markdownProfile: configuration.markdownProfile,
            isStreaming: configuration.isStreaming,
            baseFont: configuration.baseFont,
            linkColor: tintColor.resolvedColor(with: traitCollection)
        )
    }

    /// Lays streaming text out off the main thread, one layout at a time and of the latest text, so that a burst of chunks
    /// costs one layout and a long answer leaves the main thread only its Markdown rendering, 2 ms at 4000 characters
    private func scheduleStreamingLayout() {
        guard !isStreamingLayoutPending else { return }
        isStreamingLayoutPending = true
        let generation = streamingLayoutGeneration
        let delay = lastStreamingLayoutStartTime + AgentStreamingTextMetrics.streamingLayoutInterval - CACurrentMediaTime()
        DispatchQueue.main.asyncAfter(deadline: .now() + max(delay, 0)) { [weak self] in
            guard let self, generation == self.streamingLayoutGeneration else { return }
            self.startStreamingLayout(generation: generation)
        }
    }

    private func startStreamingLayout(generation: Int) {
        guard let configuration = appliedConfiguration else { return }
        lastStreamingLayoutStartTime = CACurrentMediaTime()
        let attributedString = makeAttributedText(for: configuration)
        let maxWidth = layoutMaxWidth
        let scale = UIScreen.main.scale
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let newLayout = AgentStreamingTextLayout.make(attributedString: attributedString, maxWidth: maxWidth, scale: scale)
            DispatchQueue.main.async { [weak self] in
                guard let self, generation == self.streamingLayoutGeneration else { return }
                self.isStreamingLayoutPending = false
                self.applyStreamingLayout(newLayout)
                if self.appliedConfiguration != configuration || abs(self.layoutMaxWidth - maxWidth) >= 0.5 {
                    self.scheduleStreamingLayout()
                }
            }
        }
    }

    private func cancelStreamingLayout() {
        streamingLayoutGeneration += 1
        isStreamingLayoutPending = false
    }

    private func applyStreamingLayout(_ newLayout: AgentStreamingTextLayout) {
        applyLayout(newLayout, keepingReveal: true)
        updateRevealAnimation(hasStreaming: true, hadStreaming: false)
    }

    private func applyLayout(_ newLayout: AgentStreamingTextLayout, keepingReveal: Bool) {
        layout = newLayout

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let cgImage = newLayout.renderedImage {
            renderImageView.image = UIImage(cgImage: cgImage, scale: UIScreen.main.scale, orientation: .up)
        } else {
            renderImageView.image = nil
        }
        CATransaction.commit()

        renderContainerWidthConstraint?.constant = max(newLayout.fullSize.width, 1)
        renderContainerHeightConstraint?.constant = max(newLayout.fullSize.height, 1)

        if keepingReveal {
            if revealCharacterCount == nil {
                revealCharacterCount = previousRevealCharacterCount
            }
            revealCharacterCount = min(revealCharacterCount ?? 0, newLayout.totalCharacterCount)
            previousRevealCharacterCount = min(previousRevealCharacterCount, newLayout.totalCharacterCount)
            pruneSnippetsInvalidated(by: newLayout)
            updateRevealMask()
        } else {
            revealCharacterCount = nil
            previousRevealCharacterCount = newLayout.totalCharacterCount
            detachRevealMask()
        }

        updateVisibleSize()
    }

    private func updateRevealAnimation(hasStreaming: Bool, hadStreaming: Bool) {
        guard let layout else { return }
        let totalCount = layout.totalCharacterCount
        let now = CACurrentMediaTime()

        if hasStreaming, let controller = revealController, controller.isFinalizing {
            stopRevealAnimation(resetController: true)
        }

        if revealController == nil, hasStreaming || hadStreaming {
            revealController = AgentTextRevealController(
                initialRevealedCount: previousRevealCharacterCount,
                initialLength: totalCount,
                durationMultiplier: AgentStreamingTextMetrics.revealDurationMultiplier
            )
        }

        guard let controller = revealController else { return }

        if hasStreaming {
            controller.observeUpdate(latestLength: totalCount, at: now)
        } else if hadStreaming {
            controller.finalize(finalLength: totalCount)
        }

        // Completion waits for the next tick, so it never runs inside `configure` and the cell's layout pass
        if displayLinkSubscriptionID == nil {
            displayLinkSubscriptionID = AgentDisplayLinkDriver.shared.add { [weak self] in
                self?.handleRevealTick()
            }
        }
    }

    private func handleRevealTick() {
        guard let controller = revealController else { return }

        let now = CACurrentMediaTime()
        let (revealedCount, isComplete) = controller.tick(now: now)
        let hadFinishedSnippets = removeFinishedSnippetLayers()

        if revealedCount != revealCharacterCount {
            advanceReveal(to: revealedCount)
        } else {
            if hadFinishedSnippets {
                updateRevealMask()
            }
            updateVisibleSize()
        }

        // Final content can replace this view on completion, so the last glyphs settle in their own colours first
        let appearanceDuration = AgentStreamedCharacterAppearance.getDuration(
            isMotionReduced: UIAccessibility.isReduceMotionEnabled
        )
        guard isComplete, isHeightSettled, isWidthSettled,
              now - lastSnippetSpawnTime >= appearanceDuration else { return }
        completeRevealAnimation()
    }

    private var isHeightSettled: Bool {
        abs(pendingTargetHeight - displayedVisibleHeight) < AgentStreamingTextMetrics.heightSettleThreshold
    }

    private var isWidthSettled: Bool {
        abs(pendingTargetWidth - appliedVisibleWidth) < AgentStreamingTextMetrics.heightSettleThreshold
    }

    private func advanceReveal(to characterCount: Int) {
        guard let layout else { return }

        let clampedCount = min(characterCount, layout.totalCharacterCount)
        revealCharacterCount = clampedCount

        if clampedCount > previousRevealCharacterCount {
            spawnSnippets(from: previousRevealCharacterCount, to: clampedCount, layout: layout)
            previousRevealCharacterCount = clampedCount
            lastSnippetSpawnTime = CACurrentMediaTime()
        }

        updateRevealMask()
        updateVisibleSize()
    }

    private func completeRevealAnimation() {
        stopRevealAnimation(resetController: true)

        guard isInStreamingMode || isDrainingSnippets || revealCharacterCount != nil else { return }

        if let layout, previousRevealCharacterCount < layout.totalCharacterCount {
            advanceReveal(to: layout.totalCharacterCount)
        }

        revealCharacterCount = nil
        isInStreamingMode = false
        isDrainingSnippets = true
        allowsLinkInteraction = finalizedAllowsLinks
        updateVisibleSize()
        finishSnippetDrainIfPossible()

        onRevealCompleted?()
    }

    private func finishSnippetDrainIfPossible() {
        guard isDrainingSnippets, animatingSnippetLayers.isEmpty else { return }
        isDrainingSnippets = false
        detachRevealMask()
    }

    private func stopRevealAnimation(resetController: Bool = false) {
        if let displayLinkSubscriptionID {
            AgentDisplayLinkDriver.shared.remove(displayLinkSubscriptionID)
            self.displayLinkSubscriptionID = nil
        }
        if resetController {
            revealController = nil
        }
        if hasFinishedSnippets {
            scheduleFinishedSnippetRemoval()
        }
    }

    private func spawnSnippets(from startIndex: Int, to endIndex: Int, layout: AgentStreamingTextLayout) {
        guard let contents = layout.renderedImage else { return }
        let layerSize = layout.fullSize
        guard layerSize.width > 0, layerSize.height > 0 else { return }

        var lineStartIndex = 0
        var lastSpawnedRect = CGRect.null

        for line in layout.lines {
            let lineCount = line.characterRects.count
            defer { lineStartIndex += lineCount }

            if lineStartIndex + lineCount <= startIndex { continue }
            if lineStartIndex >= endIndex { break }

            let firstInLine = max(0, startIndex - lineStartIndex)
            let lastInLine = min(lineCount, endIndex - lineStartIndex)

            for index in firstInLine..<lastInLine {
                guard animatingSnippetLayers.count < AgentStreamingTextMetrics.maximumAnimatingSnippetCount else { return }
                let charRect = line.characterRects[index]
                if charRect.isEmpty || charRect.width < 0.5 { continue }
                if charRect == lastSpawnedRect { continue }
                lastSpawnedRect = charRect

                let restingRect = CGRect(
                    x: charRect.minX,
                    y: line.frame.minY,
                    width: charRect.width,
                    height: line.frame.height
                )

                let snippetLayer = AgentRevealSnippetLayer(
                    characterIndex: lineStartIndex + index,
                    restingFrame: restingRect
                )
                let contentsRect = CGRect(
                    x: restingRect.minX / layerSize.width,
                    y: restingRect.minY / layerSize.height,
                    width: restingRect.width / layerSize.width,
                    height: restingRect.height / layerSize.height
                )
                snippetLayer.contents = contents
                snippetLayer.contentsRect = contentsRect
                snippetLayer.contentsGravity = .resize
                snippetLayer.frame = restingRect

                renderContainer.layer.insertSublayer(snippetLayer, below: blueAccentLayer)
                animatingSnippetLayers.append(snippetLayer)
                animateSnippet(snippetLayer)
                if !UIAccessibility.isReduceMotionEnabled {
                    addAccent(over: snippetLayer, contents: contents, contentsRect: contentsRect)
                }
            }
        }
        updateAccentRegion()
    }

    /// The character comes out of a blur and transparent, sharp within `sharpenDuration`: a glow of its own shape in the
    /// Agent's blue fades as it does. Once sharp, the static text shows it, under the Agent's colours that `addAccent`
    /// fades.
    private func animateSnippet(_ snippetLayer: AgentRevealSnippetLayer) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { [weak self, weak snippetLayer] in
            guard let self, let snippetLayer else { return }
            snippetLayer.isFinished = true
            self.hasFinishedSnippets = true
            self.scheduleFinishedSnippetRemoval()
        }

        let duration = AgentStreamedCharacterAppearance.sharpenDuration
        let isMotionReduced = UIAccessibility.isReduceMotionEnabled
        // A snapshot of the layer tree, such as a cross-dissolve, shows the model opacity, so it stays at the start value
        snippetLayer.opacity = 0
        let alpha = CABasicAnimation(keyPath: "opacity")
        alpha.fromValue = isMotionReduced ? 0 : AgentStreamedCharacterAppearance.initialOpacity
        alpha.toValue = 1.0
        alpha.duration = duration
        alpha.timingFunction = CAMediaTimingFunction(name: .easeOut)
        alpha.fillMode = .forwards
        alpha.isRemovedOnCompletion = false
        snippetLayer.add(alpha, forKey: "revealOpacity")

        if !isMotionReduced {
            // The glow is the blur: the glyph's shadow in the Agent's blue, gone by the time the glyph is sharp. Its
            // opacity rests at 0, so a settled glyph draws no shadow.
            snippetLayer.shadowColor = AgentGlowPalette.textBlue.resolvedColor(with: traitCollection).cgColor
            snippetLayer.shadowOffset = .zero
            snippetLayer.shadowRadius = 0
            snippetLayer.shadowOpacity = 0
            let glow = CABasicAnimation(keyPath: "shadowOpacity")
            glow.fromValue = AgentStreamedCharacterAppearance.initialGlowOpacity
            glow.toValue = 0
            let blur = CABasicAnimation(keyPath: "shadowRadius")
            blur.fromValue = AgentStreamedCharacterAppearance.initialGlowRadius
            blur.toValue = 0
            for animation in [glow, blur] {
                animation.duration = duration
                animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
                snippetLayer.add(animation, forKey: "reveal" + (animation.keyPath ?? ""))
            }
        }

        CATransaction.commit()
    }

    /// The character starts in the Agent's blue, which turns violet and then into its own colour, a link's or code's
    /// included, within `colorDuration` after it is sharp: a copy of it in each colour's mask fades in with it and then
    /// out, the violet one over the blue one
    private func addAccent(over snippetLayer: AgentRevealSnippetLayer, contents: Any, contentsRect: CGRect) {
        func makeCopy() -> AgentRevealSnippetLayer {
            let characterLayer = AgentRevealSnippetLayer(
                characterIndex: snippetLayer.characterIndex,
                restingFrame: snippetLayer.restingFrame
            )
            characterLayer.contents = contents
            characterLayer.contentsRect = contentsRect
            characterLayer.contentsGravity = .resize
            characterLayer.frame = snippetLayer.restingFrame
            characterLayer.opacity = 0
            return characterLayer
        }
        let blueCopy = makeCopy()
        let violetCopy = makeCopy()

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { [weak self, weak blueCopy, weak violetCopy] in
            self?.removeAccentCharacterLayers { $0 === blueCopy || $0 === violetCopy }
        }
        blueAccentLayer.backgroundColor = AgentGlowPalette.textBlue.resolvedColor(with: traitCollection).cgColor
        violetAccentLayer.backgroundColor = AgentGlowPalette.textViolet.resolvedColor(with: traitCollection).cgColor
        let keyframes = AgentStreamedCharacterAppearance.tintKeyframes
        let total = AgentStreamedCharacterAppearance.sharpenDuration + AgentStreamedCharacterAppearance.colorDuration
        for (accentLayer, characterLayer, values) in [
            (blueAccentLayer, blueCopy, keyframes.blue),
            (violetAccentLayer, violetCopy, keyframes.violet),
        ] {
            accentLayer.mask?.addSublayer(characterLayer)
            accentCharacterLayers.append(characterLayer)
            let tint = CAKeyframeAnimation(keyPath: "opacity")
            tint.values = values
            tint.keyTimes = keyframes.keyTimes
            tint.duration = total
            characterLayer.add(tint, forKey: "accent")
        }
        CATransaction.commit()
    }

    private func removeAccentCharacterLayers(where shouldRemove: (AgentRevealSnippetLayer) -> Bool) {
        var survivors: [AgentRevealSnippetLayer] = []
        for layer in accentCharacterLayers {
            if shouldRemove(layer) {
                layer.removeFromSuperlayer()
            } else {
                survivors.append(layer)
            }
        }
        guard survivors.count != accentCharacterLayers.count else { return }
        accentCharacterLayers = survivors
        updateAccentRegion()
    }

    /// Sizes the Agent's colours to the characters that still show them, which keeps their offscreen passes to the last
    /// few lines
    private func updateAccentRegion() {
        let region = accentCharacterLayers.reduce(CGRect.null) { $0.union($1.restingFrame) }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for accentLayer in accentLayers {
            accentLayer.isHidden = region.isNull
            guard !region.isNull, let maskLayer = accentLayer.mask else { continue }
            // Bounds at the region's origin keep the character copies in the text's coordinates
            accentLayer.frame = region
            accentLayer.bounds.origin = region.origin
            maskLayer.frame = region
            maskLayer.bounds.origin = region.origin
        }
        CATransaction.commit()
    }

    /// A finished glyph stays in its final state until the next frame, which removes all of them and rebuilds the mask once
    private func scheduleFinishedSnippetRemoval() {
        guard displayLinkSubscriptionID == nil, !isFinishedSnippetRemovalScheduled else { return }
        isFinishedSnippetRemovalScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isFinishedSnippetRemovalScheduled = false
            guard self.removeFinishedSnippetLayers() else { return }
            self.updateRevealMask()
            self.finishSnippetDrainIfPossible()
        }
    }

    private func removeFinishedSnippetLayers() -> Bool {
        guard hasFinishedSnippets else { return false }
        hasFinishedSnippets = false
        animatingSnippetLayers.removeAll { snippetLayer in
            guard snippetLayer.isFinished else { return false }
            snippetLayer.removeFromSuperlayer()
            return true
        }
        return true
    }

    private func removeAllSnippets() {
        for snippetLayer in animatingSnippetLayers {
            snippetLayer.removeFromSuperlayer()
        }
        animatingSnippetLayers.removeAll()
        removeAccentCharacterLayers { _ in true }
    }

    private func pruneSnippetsInvalidated(by newLayout: AgentStreamingTextLayout) {
        // A character the new layout moves, as a word wrapping onto the next line, shows where it lands at once
        func isStill(_ layer: AgentRevealSnippetLayer) -> Bool {
            guard let newRect = newLayout.characterRect(at: layer.characterIndex) else { return false }
            return abs(newRect.minX - layer.restingFrame.minX) < 0.5
                && abs(newRect.minY - layer.restingFrame.minY) < 0.5
                && abs(newRect.width - layer.restingFrame.width) < 0.5
        }
        removeAccentCharacterLayers { !isStill($0) }
        guard !animatingSnippetLayers.isEmpty else { return }

        var survivors: [AgentRevealSnippetLayer] = []
        for snippetLayer in animatingSnippetLayers {
            if isStill(snippetLayer) {
                survivors.append(snippetLayer)
            } else {
                snippetLayer.removeFromSuperlayer()
            }
        }
        animatingSnippetLayers = survivors
    }

    private func updateRevealMask() {
        guard let layout, layout.renderedImage != nil else { return }

        let frontier: Int
        if let revealCharacterCount {
            frontier = revealCharacterCount
        } else if isDrainingSnippets {
            frontier = layout.totalCharacterCount
        } else {
            detachRevealMask()
            return
        }

        let snippetBounds = animatingSnippetLayers.reduce(CGRect.null) { $0.union($1.restingFrame) }
        let coveredPath = UIBezierPath()
        let path = UIBezierPath()
        var remaining = frontier
        var settledHeight: CGFloat = 0
        var isAmongSettledLines = true

        for line in layout.lines {
            if remaining <= 0 { break }

            let lineCount = line.characterRects.count
            let revealCount = min(remaining, lineCount)
            remaining -= lineCount

            // Lines above the animating glyphs share one rectangle, so a long answer costs what a short one does
            if isAmongSettledLines, revealCount == lineCount, snippetBounds.isNull || line.frame.maxY <= snippetBounds.minY {
                settledHeight = line.frame.maxY
                continue
            }
            isAmongSettledLines = false

            for index in 0..<revealCount {
                let rect = line.characterRects[index]
                guard !rect.isEmpty else { continue }
                let destination = rect.integral.intersects(snippetBounds) ? coveredPath : path
                destination.append(UIBezierPath(rect: rect.integral))
            }
        }

        if settledHeight > 0 {
            path.append(UIBezierPath(rect: CGRect(x: 0, y: 0, width: layout.fullSize.width, height: settledHeight)))
        }

        if !coveredPath.isEmpty {
            let snippetPath = UIBezierPath()
            for snippetLayer in animatingSnippetLayers {
                snippetPath.append(UIBezierPath(rect: snippetLayer.restingFrame))
            }
            // Hide the static glyphs beneath their animated copies without cancelling overlapping RTL/ligature bounds.
            path.append(UIBezierPath(cgPath: coveredPath.cgPath.subtracting(snippetPath.cgPath, using: .winding)))
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        revealMaskLayer.fillRule = .nonZero
        revealMaskLayer.path = path.cgPath
        revealMaskLayer.frame = CGRect(origin: .zero, size: layout.fullSize)
        renderImageView.layer.mask = revealMaskLayer

        CATransaction.commit()
    }

    private func detachRevealMask() {
        renderImageView.layer.mask = nil
        revealMaskLayer.path = nil
    }

    private func currentDisplaySize() -> CGSize {
        guard let layout else { return .zero }
        if let revealCharacterCount {
            return layout.size(forCharacterCount: revealCharacterCount)
        }
        return layout.fullSize
    }

    private func updateVisibleSize() {
        if !isInStreamingMode, let layout {
            let fullSize = layout.fullSize
            let staticHeight = max(fullSize.height, AgentStreamingTextMetrics.minimumVisibleHeight)
            let staticWidth = max(fullSize.width, 1)
            displayedVisibleHeight = staticHeight
            displayedVisibleWidth = staticWidth
            appliedVisibleWidth = staticWidth
            pendingTargetHeight = staticHeight
            pendingTargetWidth = staticWidth
            lastHeightSmoothingTime = nil
            lastWidthSmoothingTime = nil
            revealedWidthConstraint?.constant = staticWidth
            revealedHeightConstraint?.constant = staticHeight
            revealedWidthConstraint?.isActive = true
            revealedHeightConstraint?.isActive = true
            let staticSize = CGSize(width: staticWidth, height: staticHeight)
            guard abs(staticSize.width - lastReportedSize.width) > 0.5
                || abs(staticSize.height - lastReportedSize.height) > 0.5 else { return }
            lastReportedSize = staticSize
            invalidateIntrinsicContentSize()
            guard !isSoftReusePending else { return }
            onPreferredHeightChanged?(false)
            return
        }

        let displaySize = currentDisplaySize()
        let targetHeight = max(displaySize.height, AgentStreamingTextMetrics.minimumVisibleHeight)
        pendingTargetHeight = targetHeight

        let naturalWidth = max(displaySize.width, 1)
        let knownMaxWidth = max(layout?.fullSize.width ?? naturalWidth, naturalWidth)
        pendingTargetWidth = knownMaxWidth

        let visibleSize = CGSize(
            width: max(naturalWidth, easedWidth(towardTarget: knownMaxWidth, naturalMinimum: naturalWidth)),
            height: easedHeight(towardTarget: targetHeight)
        )
        appliedVisibleWidth = visibleSize.width
        revealedWidthConstraint?.constant = visibleSize.width
        revealedHeightConstraint?.constant = visibleSize.height
        if layout != nil {
            revealedWidthConstraint?.isActive = true
            revealedHeightConstraint?.isActive = true
        }

        let widthChanged = abs(visibleSize.width - lastReportedSize.width) > 0.5
        let heightChanged = abs(visibleSize.height - lastReportedSize.height) > 0.5
        guard widthChanged || heightChanged else { return }

        lastReportedSize = visibleSize
        invalidateIntrinsicContentSize()
        guard !isSoftReusePending else { return }
        onPreferredHeightChanged?(false)
    }

    private func easedHeight(towardTarget target: CGFloat) -> CGFloat {
        guard isInStreamingMode || isDrainingSnippets else {
            displayedVisibleHeight = target
            lastHeightSmoothingTime = nil
            return target
        }

        let now = CACurrentMediaTime()
        guard let lastTime = lastHeightSmoothingTime else {
            lastHeightSmoothingTime = now
            displayedVisibleHeight = target
            return target
        }
        lastHeightSmoothingTime = now

        let dt = min(now - lastTime, AgentStreamingTextMetrics.heightSmoothingFrameDtCap)
        let smoothing = min(1.0, dt / AgentStreamingTextMetrics.heightSmoothingTau)
        displayedVisibleHeight += (target - displayedVisibleHeight) * smoothing
        if abs(target - displayedVisibleHeight) < AgentStreamingTextMetrics.heightSettleThreshold {
            displayedVisibleHeight = target
        }
        return displayedVisibleHeight
    }

    private func easedWidth(towardTarget target: CGFloat, naturalMinimum: CGFloat) -> CGFloat {
        guard isInStreamingMode else {
            displayedVisibleWidth = target
            lastWidthSmoothingTime = nil
            return target
        }

        let now = CACurrentMediaTime()
        guard let lastTime = lastWidthSmoothingTime else {
            lastWidthSmoothingTime = now
            displayedVisibleWidth = naturalMinimum
            return displayedVisibleWidth
        }
        lastWidthSmoothingTime = now

        let dt = min(now - lastTime, AgentStreamingTextMetrics.heightSmoothingFrameDtCap)
        let smoothing = min(1.0, dt / AgentStreamingTextMetrics.widthLeadSmoothingTau)
        displayedVisibleWidth += (target - displayedVisibleWidth) * smoothing
        if abs(target - displayedVisibleWidth) < AgentStreamingTextMetrics.heightSettleThreshold {
            displayedVisibleWidth = target
        }
        return displayedVisibleWidth
    }
}
