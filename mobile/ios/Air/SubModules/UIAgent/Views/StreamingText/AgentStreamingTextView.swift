import UIKit

private enum AgentStreamingTextMetrics {
    static let minimumLayoutWidth: CGFloat = 120
    static let minimumVisibleHeight: CGFloat = 20
    static let bubbleMaxWidthMultiplier: CGFloat = 0.8
    static let bubbleBodyHorizontalPadding: CGFloat = 14

    static let snippetFadeDuration: TimeInterval = 0.2
    static let snippetRiseOffset: CGFloat = 6.0
    static let snippetInitialScale: CGFloat = 0.5
    static let revealDurationMultiplier: Double = 1.0
    static let heightSmoothingTau: TimeInterval = 0.14
    static let heightSmoothingFrameDtCap: TimeInterval = 0.05
    static let heightSettleThreshold: CGFloat = 0.5
    static let widthLeadSmoothingTau: TimeInterval = 0.4
}

private final class AgentRevealSnippetLayer: CALayer {
    let characterIndex: Int
    let restingFrame: CGRect

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

@MainActor
final class AgentStreamingTextView: UIView {
    var onPreferredHeightChanged: ((_ animated: Bool) -> Void)?
    var onRevealCompleted: (() -> Void)?
    var onURLTap: ((URL) -> Void)?

    private let renderContainer = UIView()
    private let renderImageView = UIImageView()
    private let revealMaskLayer = CAShapeLayer()
    private var animatingSnippetLayers: [AgentRevealSnippetLayer] = []

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
    private var lastAppliedRenderContainerOffset: CGFloat = 0

    private var displayedVisibleHeight: CGFloat = AgentStreamingTextMetrics.minimumVisibleHeight
    private var pendingTargetHeight: CGFloat = AgentStreamingTextMetrics.minimumVisibleHeight
    private var lastHeightSmoothingTime: Double?
    private var displayedVisibleWidth: CGFloat = 1
    private var lastWidthSmoothingTime: Double?

    private func pointInRenderContainer(_ point: CGPoint) -> CGPoint {
        renderContainer.convert(point, from: self)
    }

    private struct PendingConfiguration: Equatable {
        let text: String
        let textColor: UIColor
        let isStreaming: Bool
        let hadStreaming: Bool
        let rendersMarkdown: Bool
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

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) else { return }
        guard let configuration = appliedConfiguration ?? pendingConfiguration else { return }
        pendingConfiguration = configuration
        appliedConfiguration = nil
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
            width: max(displayedVisibleWidth, 1),
            height: max(displayedVisibleHeight, AgentStreamingTextMetrics.minimumVisibleHeight)
        )
    }

    func prepareForReuse() {
        isSoftReusePending = true
        stopRevealAnimation(resetController: false)
        onPreferredHeightChanged = nil
        onRevealCompleted = nil
        onURLTap = nil
    }

    private func hardResetForReuse() {
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
        renderContainer.layer.transform = CATransform3DIdentity
        lastAppliedRenderContainerOffset = 0
        displayedVisibleHeight = AgentStreamingTextMetrics.minimumVisibleHeight
        pendingTargetHeight = AgentStreamingTextMetrics.minimumVisibleHeight
        lastHeightSmoothingTime = nil
        displayedVisibleWidth = 1
        lastWidthSmoothingTime = nil
        invalidateIntrinsicContentSize()
    }

    func configure(
        text: String,
        textColor: UIColor,
        isStreaming: Bool,
        hadStreaming: Bool,
        rendersMarkdown: Bool,
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
            allowsLinks: allowsLinks
        )
        self.layoutMaxWidth = max(AgentStreamingTextMetrics.minimumLayoutWidth, layoutMaxWidth)
        applyPendingConfigurationIfPossible()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateRenderContainerOffset()

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
        backgroundColor = .clear
        clipsToBounds = false

        renderContainer.backgroundColor = .clear
        renderContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(renderContainer)

        renderImageView.contentMode = .topLeft
        renderImageView.translatesAutoresizingMaskIntoConstraints = false
        renderContainer.addSubview(renderImageView)

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

    private func updateRenderContainerOffset() {
        let contentWidth = renderContainerWidthConstraint?.constant ?? 0
        let offset = max(0, ((bounds.width - contentWidth) / 2).rounded())
        guard abs(offset - lastAppliedRenderContainerOffset) > 0.5 else { return }
        let delta = offset - lastAppliedRenderContainerOffset
        lastAppliedRenderContainerOffset = offset

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        renderContainer.layer.transform = CATransform3DMakeTranslation(offset, 0, 0)
        CATransaction.commit()

        repositionSnippets(byDeltaX: delta)
    }

    private func repositionSnippets(byDeltaX delta: CGFloat) {
        guard delta != 0, !animatingSnippetLayers.isEmpty else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for snippetLayer in animatingSnippetLayers {
            snippetLayer.frame.origin.x += delta
        }
        CATransaction.commit()
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

        allowsLinkInteraction = configuration.allowsLinks
            && !configuration.isStreaming
            && !isInStreamingMode

        let rendered = AgentMessageTextRenderer.makeAttributedText(
            configuration.text,
            textColor: configuration.textColor.resolvedColor(with: traitCollection),
            rendersMarkdown: configuration.rendersMarkdown,
            detectsLinks: configuration.allowsLinks
        )

        if configuration.isStreaming {
            isInStreamingMode = true
            finalizedAllowsLinks = configuration.allowsLinks
            applyLayout(for: rendered, keepingReveal: true)
            updateRevealAnimation(hasStreaming: true, hadStreaming: false)
            return
        }

        if configuration.hadStreaming, isInStreamingMode {
            finalizedAllowsLinks = configuration.allowsLinks
            applyLayout(for: rendered, keepingReveal: true)
            updateRevealAnimation(hasStreaming: false, hadStreaming: true)
            return
        }

        isInStreamingMode = false
        isDrainingSnippets = false
        stopRevealAnimation(resetController: true)
        removeAllSnippets()
        applyLayout(for: rendered, keepingReveal: false)
        allowsLinkInteraction = configuration.allowsLinks
    }

    private func applyLayout(for attributedText: NSAttributedString, keepingReveal: Bool) {
        let newLayout = AgentStreamingTextLayout.make(attributedString: attributedText, maxWidth: layoutMaxWidth)
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

        if controller.isFinalizing, Int(controller.revealedCount) >= controller.latestLength,
           isHeightSettled, isWidthSettled {
            completeRevealAnimation()
            return
        }

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

        if revealedCount != revealCharacterCount {
            advanceReveal(to: revealedCount)
        } else {
            updateVisibleSize()
        }

        guard isComplete, isHeightSettled, isWidthSettled else { return }
        completeRevealAnimation()
    }

    private var isHeightSettled: Bool {
        abs(pendingTargetHeight - displayedVisibleHeight) < AgentStreamingTextMetrics.heightSettleThreshold
    }

    private var isWidthSettled: Bool {
        let knownMaxWidth = layout?.fullSize.width ?? displayedVisibleWidth
        return abs(knownMaxWidth - displayedVisibleWidth) < AgentStreamingTextMetrics.heightSettleThreshold
    }

    private func advanceReveal(to characterCount: Int) {
        guard let layout else { return }

        let clampedCount = min(characterCount, layout.totalCharacterCount)
        revealCharacterCount = clampedCount

        if clampedCount > previousRevealCharacterCount {
            spawnSnippets(from: previousRevealCharacterCount, to: clampedCount, layout: layout)
            previousRevealCharacterCount = clampedCount
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
                snippetLayer.frame = restingRect.offsetBy(dx: lastAppliedRenderContainerOffset, dy: 0)

                self.layer.addSublayer(snippetLayer)
                animatingSnippetLayers.append(snippetLayer)
                animateSnippet(snippetLayer)
            }
        }
    }

    private func animateSnippet(_ snippetLayer: AgentRevealSnippetLayer) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { [weak self, weak snippetLayer] in
            guard let self, let snippetLayer else { return }
            snippetLayer.removeFromSuperlayer()
            self.animatingSnippetLayers.removeAll { $0 === snippetLayer }
            self.updateRevealMask()
            self.finishSnippetDrainIfPossible()
        }

        let fadeDuration = AgentStreamingTextMetrics.snippetFadeDuration

        let alpha = CABasicAnimation(keyPath: "opacity")
        alpha.fromValue = 0.0
        alpha.toValue = 1.0
        alpha.duration = fadeDuration
        alpha.timingFunction = CAMediaTimingFunction(name: .easeOut)
        snippetLayer.add(alpha, forKey: "revealOpacity")

        let rise = CABasicAnimation(keyPath: "position.y")
        rise.fromValue = AgentStreamingTextMetrics.snippetRiseOffset
        rise.toValue = 0.0
        rise.isAdditive = true
        rise.duration = fadeDuration
        rise.timingFunction = CAMediaTimingFunction(name: .easeOut)
        snippetLayer.add(rise, forKey: "revealRise")

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = AgentStreamingTextMetrics.snippetInitialScale
        scale.toValue = 1.0
        scale.duration = fadeDuration
        scale.timingFunction = CAMediaTimingFunction(name: .easeOut)
        snippetLayer.add(scale, forKey: "revealScale")

        CATransaction.commit()
    }

    private func removeAllSnippets() {
        for snippetLayer in animatingSnippetLayers {
            snippetLayer.removeFromSuperlayer()
        }
        animatingSnippetLayers.removeAll()
    }

    private func pruneSnippetsInvalidated(by newLayout: AgentStreamingTextLayout) {
        guard !animatingSnippetLayers.isEmpty else { return }

        var survivors: [AgentRevealSnippetLayer] = []
        for snippetLayer in animatingSnippetLayers {
            if let newRect = newLayout.characterRect(at: snippetLayer.characterIndex),
               abs(newRect.minX - snippetLayer.restingFrame.minX) < 0.5,
               abs(newRect.minY - snippetLayer.restingFrame.minY) < 0.5,
               abs(newRect.width - snippetLayer.restingFrame.width) < 0.5 {
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

        let path = UIBezierPath()
        var remaining = frontier

        for line in layout.lines {
            if remaining <= 0 { break }

            let lineCount = line.characterRects.count
            let revealCount = min(remaining, lineCount)

            if revealCount > 0 {
                var revealedMaxX: CGFloat = 0
                for index in 0..<revealCount {
                    revealedMaxX = max(revealedMaxX, line.characterRects[index].maxX)
                }
                if revealedMaxX > 0 {
                    path.append(UIBezierPath(rect: CGRect(
                        x: 0,
                        y: line.frame.minY,
                        width: ceil(revealedMaxX),
                        height: line.frame.height
                    )))
                }
            }

            remaining -= lineCount
        }

        for snippetLayer in animatingSnippetLayers {
            path.append(UIBezierPath(rect: snippetLayer.restingFrame))
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        revealMaskLayer.fillRule = .evenOdd
        revealMaskLayer.path = path.cgPath
        revealMaskLayer.frame = CGRect(origin: .zero, size: layout.fullSize)
        renderContainer.layer.mask = revealMaskLayer

        CATransaction.commit()
    }

    private func detachRevealMask() {
        renderContainer.layer.mask = nil
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
            pendingTargetHeight = staticHeight
            lastHeightSmoothingTime = nil
            lastWidthSmoothingTime = nil
            revealedWidthConstraint?.constant = staticWidth
            revealedHeightConstraint?.constant = staticHeight
            revealedWidthConstraint?.isActive = true
            revealedHeightConstraint?.isActive = true
            updateRenderContainerOffset()
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

        let visibleSize = CGSize(
            width: max(naturalWidth, easedWidth(towardTarget: knownMaxWidth, naturalMinimum: naturalWidth)),
            height: easedHeight(towardTarget: targetHeight)
        )
        revealedWidthConstraint?.constant = visibleSize.width
        revealedHeightConstraint?.constant = visibleSize.height
        if layout != nil {
            revealedWidthConstraint?.isActive = true
            revealedHeightConstraint?.isActive = true
        }
        updateRenderContainerOffset()

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
