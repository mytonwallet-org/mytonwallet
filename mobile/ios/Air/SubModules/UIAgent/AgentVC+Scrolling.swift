import UIKit
import UIComponents

extension AgentVC: AgentChatListScrolling {
    /// The list following the covered area is where it is heading
    var headingContentOffsetY: CGFloat {
        occlusionFollow?.endOffsetY ?? collectionView.contentOffset.y
    }

    /// The scroll-to-bottom button keeps clear of the recording circle, as Telegram's navigation buttons do
    var isScrollToBottomButtonHeld: Bool {
        composerView.isRecordingCircleVisible
    }

    func listDidEndScrollingToLatest() {
        lastVisibleRowAnchor = topVisibleRowAnchor()
    }

    /// A chat keeps its messages in place rather than its date lines
    func getAnchorItemID(at indexPath: IndexPath) -> AgentItemID? {
        guard let itemID = messageItemID(at: indexPath),
              case .message(let message)? = model.item(for: itemID),
              message.role != .system else { return nil }
        return itemID
    }

    func getIndexPath(forAnchorItemID itemID: AgentItemID) -> IndexPath? {
        messageIndexPath(for: itemID)
    }

    func updateOcclusionInsets() {
        guard canResolveBottomLayoutState else { return }
        let total = totalOcclusionBottomInset
        let baselineBottom = collectionView.adjustedContentInset.bottom - collectionView.contentInset.bottom
        let additional = max(0, total - baselineBottom)
        let previousOcclusion = collectionView.contentInset.bottom - reserveSpacerHeight
        if abs(previousOcclusion - additional) > 0.5,
           let followingOffsetY = getOffsetYFollowingCoveredArea(by: additional - previousOcclusion) {
            followCoveredArea(to: followingOffsetY, bottomInset: additional + reserveSpacerHeight)
        } else if abs(previousOcclusion - additional) > 0.5 {
            stopFollowingCoveredArea()
            preservingTopVisibleRow {
                // Only a question waiting for its reply keeps its place with space below; a list the user holds goes
                // back into range as UIKit's scrolling brings it there
                if additional < previousOcclusion, isPinnedArrivalInProgress {
                    fitReserveSpacer(
                        keepingOffsetY: min(collectionView.contentOffset.y, maxContentOffsetY),
                        bottomInset: baselineBottom + additional
                    )
                }
                collectionView.contentInset.bottom = additional + reserveSpacerHeight
                collectionView.layoutIfNeeded()
            }
        }
        if abs(collectionView.verticalScrollIndicatorInsets.bottom - total) > 0.5 {
            collectionView.verticalScrollIndicatorInsets.bottom = total
        }
    }

    /// Where the list goes as the area the composer and the keyboard cover changes by `delta`, if it follows that
    /// area as Telegram's chat follows the keyboard: with the content's end in view, the content rides up as the area
    /// grows, and as the area shrinks it comes down as far as it can without leaving space under its end. A list
    /// scrolled up keeps its rows in place, as does a sent question waiting for its reply.
    private func getOffsetYFollowingCoveredArea(by delta: CGFloat) -> CGFloat? {
        guard !isPinnedArrivalInProgress, !collectionView.isTracking, !collectionView.isDragging,
              let lastItemIndexPath,
              let lastFrame = collectionView.layoutAttributesForItem(at: lastItemIndexPath)?.frame else { return nil }
        let offsetY = occlusionFollow?.endOffsetY ?? collectionView.contentOffset.y
        let height = collectionView.bounds.height
        let visibleBottom = offsetY + height - occlusionBottomInset
        let isEndInView = lastFrame.maxY <= visibleBottom + AgentVCLayout.nearBottomThreshold
        let targetOffsetY: CGFloat
        if delta > 0 {
            guard isEndInView else { return nil }
            targetOffsetY = offsetY + min(delta, max(0, lastFrame.maxY - (visibleBottom - delta)))
        } else if isEndInView {
            // The last row comes down with the composer, and the row spacing under it stays out of view
            targetOffsetY = max(-collectionView.adjustedContentInset.top, lastFrame.maxY - (visibleBottom - offsetY - delta))
        } else {
            let contentHeight = collectionView.collectionViewLayout.collectionViewContentSize.height
            let maxOffsetY = contentHeight - height + collectionView.adjustedContentInset.bottom + delta
            targetOffsetY = max(-collectionView.adjustedContentInset.top, min(offsetY, maxOffsetY))
        }
        return abs(targetOffsetY - offsetY) > 0.5 ? targetOffsetY : nil
    }

    private var isPinnedArrivalInProgress: Bool {
        pinnedUserMessageID != nil
            && (isRevealingSentUserMessage || lastTypingIndicatorID != nil || isRevealingStreamedAnswer)
    }

    /// Sets the inset for the covered area and moves the list to `offsetY`. As the composer animates, the list moves in
    /// step with it, frame by frame, so the rows going off screen stay drawn as they go.
    private func followCoveredArea(to offsetY: CGFloat, bottomInset: CGFloat) {
        let startOffsetY = collectionView.contentOffset.y
        UIView.performWithoutAnimation {
            collectionView.contentInset.bottom = bottomInset
            collectionView.layoutIfNeeded()
        }
        let endComposerY = composerView.frame.minY
        let startComposerY = composerView.layer.presentation()?.frame.minY ?? lastComposerMinY ?? endComposerY
        guard UIView.inheritedAnimationDuration > 0, abs(endComposerY - startComposerY) > 0.5,
              !UIAccessibility.isReduceMotionEnabled else {
            stopFollowingCoveredArea()
            setContentOffsetY(offsetY)
            return
        }
        occlusionFollow = OcclusionFollow(
            startOffsetY: startOffsetY,
            endOffsetY: offsetY,
            startComposerY: startComposerY,
            endComposerY: endComposerY,
            startTime: CACurrentMediaTime()
        )
        occlusionFollowClock.start()
    }

    func stepFollowingCoveredArea() {
        guard let follow = occlusionFollow else {
            occlusionFollowClock.stop()
            return
        }
        let composerY = drawnComposerMinY ?? follow.endComposerY
        let progress = min(1, max(0, (composerY - follow.startComposerY) / (follow.endComposerY - follow.startComposerY)))
        let isSettled = progress > 0.999
            || composerView.layer.animationKeys()?.isEmpty != false
            || CACurrentMediaTime() - follow.startTime > Self.coveredAreaFollowTimeout
        guard !isSettled else {
            stopFollowingCoveredArea()
            setContentOffsetY(follow.endOffsetY)
            lastVisibleRowAnchor = topVisibleRowAnchor()
            lastKnownNearBottom = isNearBottom()
            updateScrollToBottomButtonVisibility(animated: false)
            return
        }
        setContentOffsetY(follow.startOffsetY + (follow.endOffsetY - follow.startOffsetY) * progress)
    }

    /// The composer's top in the frame being prepared. A layer's presentation is where it stands now, while the frame
    /// shows at the display link's target time, a frame later, and the list keeps level with the composer only when it
    /// takes the composer's place then.
    private var drawnComposerMinY: CGFloat? {
        if let time = occlusionFollowClock.targetTimestamp,
           let minY = AgentLayerAnimationSampler.getMinY(of: composerView.layer, at: time) {
            return minY
        }
        return composerView.layer.presentation()?.frame.minY
    }

    func stopFollowingCoveredArea() {
        occlusionFollow = nil
        occlusionFollowClock.stop()
    }

    private func setContentOffsetY(_ offsetY: CGFloat) {
        guard abs(collectionView.contentOffset.y - offsetY) > 0.01 else { return }
        UIView.performWithoutAnimation {
            collectionView.contentOffset.y = offsetY
        }
    }

    func applyMinimalArrivalReserveSpacerHeight(for userMessageID: AgentItemID) {
        guard let targetOffsetY = pinnedOffsetY(for: userMessageID) else { return }
        let minSpacer = max(reserveSpacerHeight, reserveSpacerHeightNeeded(toReachOffsetY: targetOffsetY))
        applyReserveSpacerHeight(minSpacer, preservingOffset: true)
    }

    func pinnedOffsetY(for userMessageID: AgentItemID) -> CGFloat? {
        guard let indexPath = messageIndexPath(for: userMessageID),
              let attributes = collectionView.layoutAttributesForItem(at: indexPath) else { return nil }
        let dateHeaderFrame = dateHeaderID(for: userMessageID)
            .flatMap(messageIndexPath(for:))
            .flatMap { collectionView.layoutAttributesForItem(at: $0)?.frame }
        let previousAnswerFrame = previousAnswerID(for: userMessageID)
            .flatMap(messageIndexPath(for:))
            .flatMap { collectionView.layoutAttributesForItem(at: $0)?.frame }
        return Self.pinnedOffsetY(
            userMessageFrame: attributes.frame,
            dateHeaderFrame: dateHeaderFrame,
            previousAnswerFrame: previousAnswerFrame,
            adjustedContentInsetTop: collectionView.adjustedContentInset.top
        )
    }

    /// Where the chat stops as it brings a sent question up: the question's top under the header, or its tail
    /// `arrivalUserMessageTailInset` below the header when it is tall. The last line of an answer right above the
    /// question stays in sight, whole with the bubble's padding under it.
    static func pinnedOffsetY(
        userMessageFrame: CGRect,
        dateHeaderFrame: CGRect?,
        previousAnswerFrame: CGRect? = nil,
        adjustedContentInsetTop: CGFloat
    ) -> CGFloat {
        if let dateHeaderFrame {
            return dateHeaderFrame.minY - adjustedContentInsetTop - AgentVCLayout.sectionTopInset
        }
        let tail = userMessageFrame.maxY - adjustedContentInsetTop - AgentVCLayout.arrivalUserMessageTailInset
        let topAligned = userMessageFrame.minY - adjustedContentInsetTop - AgentVCLayout.sectionTopInset
        guard let previousAnswerFrame else {
            return min(tail, topAligned)
        }
        let previousAnswerLineTop = previousAnswerFrame.maxY - AgentMessageCellMetrics.bodyVerticalPadding
            - AgentMessageTextRenderer.answerLineHeight
        return min(tail, topAligned, previousAnswerLineTop - adjustedContentInsetTop)
    }

    /// The answer right above a question, with nothing between them
    func previousAnswerID(for userMessageID: AgentItemID) -> AgentItemID? {
        let itemIDs = model.itemIDs
        guard let index = itemIDs.firstIndex(of: userMessageID), index > 0,
              case .message(let message)? = model.item(for: itemIDs[index - 1]),
              message.role == .assistant else { return nil }
        return message.id
    }

    func dateHeaderID(for userMessageID: AgentItemID) -> AgentItemID? {
        let itemIDs = model.itemIDs
        guard let index = itemIDs.firstIndex(of: userMessageID), index > 0,
              case .message(let message)? = model.item(for: itemIDs[index - 1]),
              message.isDateTimeSystemMessage else { return nil }
        return message.id
    }

    private func reserveSpacerHeightNeeded(toReachOffsetY offsetY: CGFloat, bottomInset: CGFloat? = nil) -> CGFloat {
        let bottom = bottomInset ?? occlusionBottomInset
        let contentHeightWithoutSpacer = collectionView.collectionViewLayout.collectionViewContentSize.height
        return max(0, offsetY + collectionView.bounds.height - bottom - contentHeightWithoutSpacer)
    }

    private func fitReserveSpacer(keepingOffsetY offsetY: CGFloat?, bottomInset: CGFloat? = nil) {
        guard reserveSpacerHeight > 0 || pinnedUserMessageID != nil else { return }
        let pinnedY = pinnedUserMessageID.flatMap(pinnedOffsetY(for:))
        let reachableOffsetY: CGFloat?
        if let offsetY, let pinnedY {
            reachableOffsetY = max(offsetY, pinnedY)
        } else {
            reachableOffsetY = offsetY ?? pinnedY
        }
        let requestedHeight = reachableOffsetY.map { reserveSpacerHeightNeeded(toReachOffsetY: $0, bottomInset: bottomInset) } ?? 0
        let height = requestedHeight < 0.5 ? 0 : requestedHeight
        guard abs(reserveSpacerHeight - height) > 0.5 else {
            // Model updates can still have pending self-sizing. A scroll-driven layout pass is already settling it.
            if !collectionView.isPreservingLayout {
                collectionView.layoutIfNeeded()
            }
            return
        }
        if (isResizingStreamingRow || collectionView.isPreservingLayout), isRevealingStreamedAnswer,
           height <= reserveSpacerHeight, reserveSpacerHeight - height <= Self.streamingReserveSpaceSlack {
            return
        }
        applyReserveSpacerHeight(height)
        collectionView.layoutIfNeeded()
    }

    private var isRevealingStreamedAnswer: Bool {
        hasActiveStreamingMessage || collectionView.visibleCells.contains {
            ($0 as? AgentMessageCell)?.isRevealingStreamedText == true
        }
    }

    func restorePinnedOffsetAfterResize(_ pinnedOffsetBeforeResize: (offsetFromPin: CGFloat, maxOffsetFromPin: CGFloat)?) {
        guard let pinnedOffsetBeforeResize else { return }
        collectionView.layoutIfNeeded()
        guard let pinnedUserMessageID, let pinnedOffsetY = pinnedOffsetY(for: pinnedUserMessageID) else { return }
        fitReserveSpacer(keepingOffsetY: pinnedOffsetY + min(
            pinnedOffsetBeforeResize.offsetFromPin,
            pinnedOffsetBeforeResize.maxOffsetFromPin
        ))
        guard let fittedPinnedOffsetY = self.pinnedOffsetY(for: pinnedUserMessageID) else { return }
        let correctedOffsetY = clampedContentOffsetY(fittedPinnedOffsetY + pinnedOffsetBeforeResize.offsetFromPin)
        if abs(collectionView.contentOffset.y - correctedOffsetY) > 0.5 {
            collectionView.contentOffset.y = correctedOffsetY
        }
    }

    func rememberPinnedPosition() {
        guard view.bounds.size == lastLayoutViewSize,
              collectionView.adjustedContentInset == lastLayoutAdjustedContentInset,
              !isResizingStreamingRow,
              let pinnedUserMessageID,
              let pinnedY = pinnedOffsetY(for: pinnedUserMessageID) else { return }
        lastPinnedPosition = (
            messageID: pinnedUserMessageID,
            offsetFromPin: collectionView.contentOffset.y - pinnedY,
            maxOffsetFromPin: maxContentOffsetY - pinnedY
        )
    }

    /// Keeps the list's scrollable extent while the row at `indexPath` leaves it: the row's place, with the spacing
    /// after it, joins the reserve under the content. An animated removal then never pulls the content offset in, which
    /// UIKit would animate as the rows above sliding, and the rows above stay where they show. Fitting the reserve
    /// after the update keeps it as long as the offset needs it.
    func reserveSpaceForLeavingRow(at indexPath: IndexPath) {
        collectionView.layoutIfNeeded()
        guard let row = collectionView.layoutAttributesForItem(at: indexPath)?.frame else { return }
        let next = IndexPath(item: indexPath.item + 1, section: indexPath.section)
        let nextMinY = next.item < collectionView.numberOfItems(inSection: indexPath.section)
            ? collectionView.layoutAttributesForItem(at: next)?.frame.minY
            : nil
        let height = (nextMinY ?? row.maxY) - row.minY
        guard height > 0.5 else { return }
        applyReserveSpacerHeight(reserveSpacerHeight + height)
    }

    private func applyReserveSpacerHeight(_ height: CGFloat, preservingOffset: Bool = false) {
        let clamped = height < 0.5 ? 0 : height
        guard abs(reserveSpacerHeight - clamped) > 0.5 else { return }

        let update = {
            let adjustment = clamped - self.reserveSpacerHeight
            self.reserveSpacerHeight = clamped
            // Scrollable padding is independent of row sizing. Resizing a spacer item repeatedly
            // invalidates historical table measurements and can create a self-sizing feedback loop.
            self.collectionView.contentInset.bottom += adjustment
            if preservingOffset {
                self.collectionView.layoutIfNeeded()
            }
        }

        if preservingOffset {
            preservingTopVisibleRow(update)
        } else {
            update()
        }
    }

    func preservingTopVisibleRow(
        anchor cachedAnchor: VisibleRowAnchor? = nil,
        fittingReserveSpacer: Bool = false,
        _ body: () -> Void
    ) {
        guard !isPreservingVisibleRow else {
            body()
            return
        }
        isPreservingVisibleRow = true
        defer {
            isPreservingVisibleRow = false
            lastVisibleRowAnchor = topVisibleRowAnchor()
        }
        let anchor = cachedAnchor ?? topVisibleRowAnchor()
        let maxOffsetYBefore = maxContentOffsetY
        body()
        guard let anchor,
              let anchorItemID = anchor.isDateHeader ? dateHeaderID(for: anchor.itemID) : anchor.itemID,
              let indexPath = messageIndexPath(for: anchorItemID),
              let frameAfter = collectionView.layoutAttributesForItem(at: indexPath)?.frame else {
            return
        }
        var shift = frameAfter.minY - anchor.minY
        if fittingReserveSpacer {
            fitReserveSpacer(keepingOffsetY: min(anchor.offsetY, maxOffsetYBefore) + shift)
            shift = (collectionView.layoutAttributesForItem(at: indexPath)?.frame.minY ?? frameAfter.minY) - anchor.minY
        }
        // Keep UIKit's overscroll and deceleration when no row has moved.
        guard abs(shift) > 0.5 || abs(collectionView.contentOffset.y - anchor.offsetY) > 0.5 else { return }
        let corrected = clampedContentOffsetY(anchor.offsetY + shift)
        if abs(collectionView.contentOffset.y - corrected) > 0.5 {
            collectionView.contentOffset.y = corrected
        }
    }

    func topVisibleRowAnchor() -> VisibleRowAnchor? {
        let offsetY = collectionView.contentOffset.y
        // Older visible answers can change height during hydration; keep the sent question in place when it is visible.
        if let pinnedUserMessageID,
           let indexPath = messageIndexPath(for: pinnedUserMessageID),
           let frame = collectionView.layoutAttributesForItem(at: indexPath)?.frame,
           frame.intersects(visibleContentRect()) {
            if let dateHeaderID = dateHeaderID(for: pinnedUserMessageID),
               let dateIndexPath = messageIndexPath(for: dateHeaderID),
               let dateFrame = collectionView.layoutAttributesForItem(at: dateIndexPath)?.frame,
               dateFrame.intersects(visibleContentRect()) {
                // Date IDs change on timeline reloads; retain the question ID to resolve its header again.
                return VisibleRowAnchor(itemID: pinnedUserMessageID, isDateHeader: true, minY: dateFrame.minY, offsetY: offsetY)
            }
            return VisibleRowAnchor(itemID: pinnedUserMessageID, isDateHeader: false, minY: frame.minY, offsetY: offsetY)
        }
        guard let anchor = collectionView.indexPathsForVisibleItems
            .compactMap({ indexPath -> (itemID: AgentItemID, frame: CGRect)? in
                guard let itemID = messageItemID(at: indexPath),
                      case .message(let message)? = model.item(for: itemID),
                      message.role != .system,
                      let attributes = collectionView.layoutAttributesForItem(at: indexPath) else { return nil }
                return (itemID: itemID, frame: attributes.frame)
            })
            .filter({ $0.frame.maxY > offsetY })
            .min(by: { $0.frame.minY < $1.frame.minY }) else {
            return nil
        }
        return VisibleRowAnchor(itemID: anchor.itemID, isDateHeader: false, minY: anchor.frame.minY, offsetY: offsetY)
    }

    /// Notes support taking or leaving the chat. Support taking a chat over a pinned question leaves the question, its
    /// reserve and the rows that came with the switch where they are; a row after them lets the question go, and the
    /// list follows new rows from then on, as `noLiveTail` does in Classic.
    func updateSupportFollowState() {
        let isActive = model.isSupportActive
        defer { wasSupportActive = isActive }
        guard isActive else {
            supportFollowResumeItemID = nil
            return
        }
        if !wasSupportActive, pinnedUserMessageID != nil {
            supportFollowResumeItemID = model.itemIDs.last
        } else if let resumeItemID = supportFollowResumeItemID, model.itemIDs.last != resumeItemID {
            supportFollowResumeItemID = nil
            pinnedUserMessageID = nil
        }
    }

    /// While support has the chat, the list follows its end as a messenger does: a new row that ends below the screen
    /// is brought into view. A sent message is taken to the end whatever the list showed. The reserve a question pinned
    /// before held goes as far as the list no longer needs it there. `completion` runs once the list is there.
    func followLatestInSupport(isSent: Bool, then completion: (() -> Void)? = nil) {
        collectionView.layoutIfNeeded()
        let finish = { [weak self] in
            guard let self else { return }
            self.trimReserveSpacerPreservingOffset()
            self.lastKnownNearBottom = self.isNearBottom()
            self.updateScrollToBottomButtonVisibility(animated: false)
            completion?()
        }
        guard let targetOffsetY = latestRowBottomOffsetY(),
              isSent ? abs(targetOffsetY - collectionView.contentOffset.y) > 0.5
                  : targetOffsetY > collectionView.contentOffset.y + 0.5 else {
            finish()
            return
        }
        guard view.window != nil, !UIAccessibility.isReduceMotionEnabled else {
            listScrollAnimator.stop()
            collectionView.setContentOffset(CGPoint(x: collectionView.contentOffset.x, y: targetOffsetY), animated: false)
            finish()
            return
        }
        collectionView.isScrollingToLatest = true
        listScrollAnimator.scroll(to: { [weak self] in self?.latestRowBottomOffsetY() }) { [weak self] _ in
            guard let self else { return }
            if self.collectionView.isScrollingToLatest {
                self.collectionView.isScrollingToLatest = false
                self.listDidEndScrollingToLatest()
            }
            finish()
        }
    }

    /// The offset that puts the latest row's bottom just above what covers the list's bottom
    private func latestRowBottomOffsetY() -> CGFloat? {
        guard let indexPath = lastItemIndexPath,
              let frame = collectionView.layoutAttributesForItem(at: indexPath)?.frame else { return nil }
        return clampedContentOffsetY(frame.maxY - collectionView.bounds.height + occlusionBottomInset)
    }

    func trimReserveSpacerPreservingOffset() {
        collectionView.layoutIfNeeded()
        let offsetY = collectionView.contentOffset.y
        let isScrolledToTop = offsetY <= -collectionView.adjustedContentInset.top + 0.5
        preservingTopVisibleRow {
            fitReserveSpacer(keepingOffsetY: isScrolledToTop ? nil : offsetY)
        }
    }

    var lastTypingIndicatorID: AgentItemID? {
        for itemID in model.itemIDs.reversed() {
            guard let item = model.item(for: itemID), case .typingIndicator = item else { continue }
            return itemID
        }
        return nil
    }

    var lastStreamingAssistantID: AgentItemID? {
        for itemID in model.itemIDs.reversed() {
            guard let item = model.item(for: itemID),
                  case .message(let message) = item,
                  message.role == .assistant,
                  message.isStreaming else {
                continue
            }
            return itemID
        }
        return nil
    }

    func visibleContentRect() -> CGRect {
        var insets = collectionView.adjustedContentInset
        insets.bottom = occlusionBottomInset
        return CGRect(
            x: collectionView.contentOffset.x + insets.left,
            y: collectionView.contentOffset.y + insets.top,
            width: collectionView.bounds.width - insets.left - insets.right,
            height: collectionView.bounds.height - insets.top - insets.bottom
        )
    }

    func revealTypingIndicatorIfNeeded() {
        guard pinnedUserMessageID == nil,
              let typingID = lastTypingIndicatorID,
              let indexPath = messageIndexPath(for: typingID) else {
            return
        }
        collectionView.layoutIfNeeded()
        guard let attributes = collectionView.layoutAttributesForItem(at: indexPath) else { return }

        let visible = visibleContentRect()
        let frame = attributes.frame
        if frame.minY >= visible.minY - 0.5, frame.maxY <= visible.maxY + 0.5 {
            return
        }
        if visible.intersects(frame.insetBy(dx: 0, dy: 1)) {
            return
        }

        var targetOffsetY = collectionView.contentOffset.y
        if frame.maxY > visible.maxY {
            targetOffsetY += frame.maxY - visible.maxY
        } else if frame.minY < visible.minY {
            targetOffsetY += frame.minY - visible.minY
        }
        targetOffsetY = clampedContentOffsetY(targetOffsetY)
        guard abs(targetOffsetY - collectionView.contentOffset.y) > 0.5 else { return }
        collectionView.setContentOffset(
            CGPoint(x: collectionView.contentOffset.x, y: targetOffsetY),
            animated: true
        )
    }

    @discardableResult
    func updateVisibleCell(itemID: AgentItemID, preparedCell: AgentMessageCell? = nil) -> Bool {
        guard let item = model.item(for: itemID),
              case .message(let message) = item,
              message.role == .assistant,
              let indexPath = messageIndexPath(for: itemID),
              let cell = preparedCell ?? collectionView.cellForItem(at: indexPath) as? AgentMessageCell else {
            return false
        }
        cell.onPreferredHeightChanged = { [weak self] _ in
            self?.handleStreamingCellHeightChanged(itemID: itemID)
        }
        cell.onStreamingRevealCompleted = { [weak self] in
            self?.handleStreamingRevealCompleted(itemID: itemID)
        }
        if message.isStreaming {
            cell.updateStreamingMessage(message)
        } else {
            cell.configure(
                with: message,
                onURLTap: { [weak self] url in self?.openMessageURL(url, renderingPolicy: message.renderingPolicy) },
                onControlTap: makeControlTapHandler(for: message) { [weak cell] in
                    cell?.getFollowupButton(controlID: $0)
                }
            )
        }
        return true
    }

    func resizeStreamingRow() {
        guard !isResizingStreamingRow else { return }
        if collectionView.isPreservingLayout {
            // Refreshing a prefetched streaming cell in willDisplay must not begin a batch
            // update while UICollectionView is still updating its visible cells.
            guard !isStreamingRowResizeScheduled else { return }
            isStreamingRowResizeScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isStreamingRowResizeScheduled = false
                self.resizeStreamingRow()
            }
            return
        }
        isResizingStreamingRow = true
        defer { isResizingStreamingRow = false }

        let batchUpdate = {
            UIView.performWithoutAnimation {
                self.collectionView.performBatchUpdates(nil)
            }
        }
        if reserveSpacerHeight > 0 || pinnedUserMessageID != nil {
            preservingTopVisibleRow(fittingReserveSpacer: true, batchUpdate)
        } else {
            batchUpdate()
        }
        lastKnownNearBottom = isNearBottom()
    }

    func isRevealingStreamedText(itemID: AgentItemID) -> Bool {
        guard let indexPath = messageIndexPath(for: itemID),
              let cell = collectionView.cellForItem(at: indexPath) as? AgentMessageCell else { return false }
        return cell.isRevealingStreamedText
    }

    func handleStreamingCellHeightChanged(itemID: AgentItemID) {
        guard model.item(for: itemID) != nil else { return }
        guard messageIndexPath(for: itemID) != nil else { return }
        wasNearBottomBeforeRowResize = isNearBottom()
        resizeStreamingRow()
    }

    /// The news post grows with follow-ups that arrive after it is shown. They show only under the latest message, so
    /// a post that is the latest and on screen scrolls them into view.
    func handleNewsPostHeightChanged(itemID: AgentItemID) {
        let indexPath = messageIndexPath(for: itemID)
        let shouldKeepFollowupsVisible = pinnedUserMessageID == nil && canResolveBottomLayoutState
            && indexPath != nil && indexPath == lastItemIndexPath
            && collectionView.indexPathsForVisibleItems.contains { $0 == indexPath }
        handleStreamingCellHeightChanged(itemID: itemID)
        if shouldKeepFollowupsVisible {
            revealLastItemIfNeeded(animated: !UIAccessibility.isReduceMotionEnabled)
        }
    }

    func handleStreamingRevealCompleted(itemID: AgentItemID) {
        guard model.item(for: itemID) != nil else { return }
        guard reserveSpacerHeight > 0 || pinnedUserMessageID != nil else { return }
        trimArrivalSpacerIfNeeded()
        if pinnedUserMessageID == nil, wasNearBottomBeforeRowResize {
            revealLastItemIfNeeded(animated: false)
            updateScrollToBottomButtonVisibility(animated: false)
        }
    }

    private func trimArrivalSpacerIfNeeded() {
        guard reserveSpacerHeight > 0 else { return }
        resizeStreamingRow()
        trimReserveSpacerPreservingOffset()
        updateScrollToBottomButtonVisibility(animated: false)
    }

    /// Opens at the latest message, at a question being answered, or at the "New" divider over the first message the
    /// user hasn't seen, as the News feed opens. Returns whether it opened at the divider.
    @discardableResult
    func performInitialScrollIfNeeded() -> Bool {
        guard !hasPerformedInitialScroll, canResolveBottomLayoutState, lastItemIndexPath != nil else { return false }
        hasPerformedInitialScroll = true
        if let initialOpeningInputItemID, pinnedUserMessageID == initialOpeningInputItemID {
            guard model.itemIDs.contains(initialOpeningInputItemID) else {
                pinnedUserMessageID = nil
                revealLastItemSettlingRowHeights()
                return false
            }
            applyMinimalArrivalReserveSpacerHeight(for: initialOpeningInputItemID)
            collectionView.layoutIfNeeded()
            if let offsetY = pinnedOffsetY(for: initialOpeningInputItemID) {
                collectionView.setContentOffset(CGPoint(x: collectionView.contentOffset.x, y: clampedContentOffsetY(offsetY)), animated: false)
            }
            return false
        }
        guard pinnedUserMessageID == nil else { return false }
        if let divider = dataSource.indexPath(for: .unreadDivider) {
            revealItemAtTop(divider)
            lastKnownNearBottom = isNearBottom()
            lastVisibleRowAnchor = topVisibleRowAnchor()
            return true
        }
        revealLastItemSettlingRowHeights()
        return false
    }

    // Reserve space extends the scroll range; it does not cover any part of the viewport.
    var occlusionBottomInset: CGFloat {
        collectionView.adjustedContentInset.bottom - reserveSpacerHeight
    }

    var canResolveBottomLayoutState: Bool {
        view.window != nil
            && collectionView.bounds.width > 0
            && collectionView.bounds.height > 0
            && composerView.inputBackgroundFrame.width > 0
            && composerView.inputBackgroundFrame.height > 0
    }
}
