import UIKit
import UIComponents

extension AgentVC: AgentModelDelegate {
    func agentModelDidReloadTimeline(animated: Bool, reconfigureItemIDs: [AgentItemID]) {
        defer {
            updateThinkingGlow()
            updateNavigationMenuAvailability()
        }
        // Rows that come back as they dissolve, as an answer whose regeneration the server turns down, simply show again
        if !dissolvingItemIDs.isEmpty, model.itemIDs.contains(where: dissolvingItemIDs.contains) {
            removeMessageDissolveView()
        }
        let previousDateAnchor = lastVisibleRowAnchor?.isDateHeader == true ? lastVisibleRowAnchor : nil
        streamingItemIDs.removeAll(keepingCapacity: true)
        updateStreamingState(for: model.itemIDs)
        deferredStreamingItemIDs.formIntersection(model.itemIDs)
        updateHintsView(animated: false)

        if paginationTask != nil {
            let paginationAnchor = paginationAnchor()
            paginationReloadGeneration += 1
            let reloadGeneration = paginationReloadGeneration
            let operationID = paginationOperationID
            applySnapshot(animated: false, reconfigureItemIDs: reconfigureItemIDs) { [weak self] in
                guard let self else { return }
                if let paginationAnchor {
                    self.restorePaginationAnchor(paginationAnchor)
                }
                self.lastKnownNearBottom = self.isNearBottom()
                self.updateScrollToBottomButtonVisibility(animated: false)
                guard let operationID, self.paginationOperationID == operationID else { return }
                self.completedPaginationReloadGeneration = max(
                    self.completedPaginationReloadGeneration,
                    reloadGeneration
                )
                self.finishPaginationIfReady(operationID: operationID)
            }
            return
        }

        // A timeline that fills an emptied chat, as when a failed clear brings the conversation back, opens at its
        // latest message, like the first one
        if snapshotMessageIDs().isEmpty {
            hasPerformedInitialScroll = false
        }
        let hasStreaming = lastStreamingAssistantID != nil
        // A question sent while an answer is written waits for it at the chat's end, where it shows without being
        // brought up
        let appendedQuestionID = appendedUserMessageID()
        let waitingUserMessageID = appendedQuestionID.flatMap { model.trailingItemIDs.contains($0) ? $0 : nil }
        let wasNearBottom = lastKnownNearBottom
        // An answer that takes the place of the typing row on screen grows out of it; other replies cross-fade in
        let replacedTypingRow = makeReplacedTypingRowSource()
        let crossfade = hasStreaming && replacedTypingRow == nil && waitingUserMessageID == nil
        var didRemoveInitialOpeningInput = false
        if let pinnedUserMessageID, !model.itemIDs.contains(pinnedUserMessageID) {
            didRemoveInitialOpeningInput = pinnedUserMessageID == initialOpeningInputItemID
            self.pinnedUserMessageID = nil
        }
        updateSupportFollowState()
        let sentUserMessageID = hasStreaming || waitingUserMessageID != nil ? nil : appendedQuestionID
        // While support has the chat, a sent message goes to the list's end, as in a messenger, and the list follows
        // new messages while it is at its end
        let isSupportActive = model.isSupportActive
        let isSentToSupport = isSupportActive && sentUserMessageID != nil
        // The scroll-to-bottom button's signal as the question comes, before the list takes it in
        revealsSentMessageFromBottom = sentUserMessageID != nil && isNearBottom() && !isSupportActive
        if isSentToSupport {
            pinnedUserMessageID = nil
        } else if let sentUserMessageID {
            pinnedUserMessageID = sentUserMessageID
        }
        let shouldFollowLatest = isSupportActive && pinnedUserMessageID == nil && (isSentToSupport || wasNearBottom)
        // The questions that wait move to their places as a row above them goes or comes, as a stopped typing row and
        // the next answer's do, while a cross-fade takes the whole list into its new rows
        let waitingRowMinYs = crossfade ? [:] : getWaitingRowScreenMinYs()
        // The rows above stay where they show, also when the rows that go leave less than a screen to scroll
        let keepsRowsAboveWaitingOnes = !crossfade && !model.trailingItemIDs.isEmpty

        var waitingAppearanceDuration: TimeInterval = 0
        let didApplyTimeline: () -> Void = { [weak self] in
            guard let self else { return }
            self.collectionView.layoutIfNeeded()
            self.updatePostSkeleton(isPostInList: true)

            if didRemoveInitialOpeningInput {
                self.hasPerformedInitialScroll = false
            }
            self.performInitialScrollIfNeeded()
            if waitingUserMessageID != nil {
                self.followWaitingUserMessage(after: waitingAppearanceDuration, followsChatEnd: wasNearBottom)
            }

            if hasStreaming {
                self.resizeStreamingRow()
                return
            }

            if shouldFollowLatest {
                self.followLatestInSupport(isSent: isSentToSupport)
            } else if self.lastTypingIndicatorID != nil {
                self.revealTypingIndicatorIfNeeded()
            } else {
                self.trimReserveSpacerPreservingOffset()
            }
            self.lastKnownNearBottom = self.isNearBottom()
            self.updateScrollToBottomButtonVisibility(animated: false)
        }
        let applyTimeline = {
            self.applySnapshot(
                animated: self.animatesNextTimelineReload,
                reconfigureItemIDs: reconfigureItemIDs,
                crossfade: crossfade,
                completion: didApplyTimeline
            )
        }
        if keepsRowsAboveWaitingOnes {
            reserveSpaceForLeavingRows()
        }
        if pinnedUserMessageID != nil || keepsRowsAboveWaitingOnes {
            let dateAnchor = previousDateAnchor.flatMap {
                $0.itemID == pinnedUserMessageID && dateHeaderID(for: $0.itemID) != nil ? $0 : nil
            }
            preservingTopVisibleRow(anchor: dateAnchor, fittingReserveSpacer: true, applyTimeline)
        } else {
            applyTimeline()
        }
        // The answer's row is in the list from this pass, and the snapshot's completion comes after a frame has shown
        // it: the morph takes the row over in this pass, so no frame shows the answer before it
        if let replacedTypingRow {
            collectionView.layoutIfNeeded()
            startTypingAnswerMorph(replacedTypingRow.source, answerID: replacedTypingRow.answerID)
        }
        // A question that waits starts turning into its bubble in this pass too, so no frame shows the bubble in place
        // before it
        if let waitingUserMessageID {
            collectionView.layoutIfNeeded()
            waitingAppearanceDuration = startWaitingUserMessageAppearance(waitingUserMessageID)
        }
        moveWaitingRows(from: waitingRowMinYs)
    }

    /// The typing row on screen whose place an answer is taking, pictured as it shows now where it shows, in the window,
    /// and the answer's id
    private func makeReplacedTypingRowSource() -> (source: AgentTypingRowSource, answerID: AgentItemID)? {
        guard let window = view.window, UIView.areAnimationsEnabled, !UIAccessibility.isReduceMotionEnabled else { return nil }
        let itemIDs = model.itemIDs
        for case let cell as AgentTypingIndicatorCell in collectionView.visibleCells {
            guard let indexPath = collectionView.indexPath(for: cell),
                  let typingID = messageItemID(at: indexPath),
                  !itemIDs.contains(typingID) else { continue }
            let shownItemIDs = snapshotMessageIDs()
            guard let index = shownItemIDs.firstIndex(of: typingID),
                  itemIDs.indices.contains(index) else { continue }
            // The answer stands where the row stood
            let answerID = itemIDs[index]
            guard !shownItemIDs.contains(answerID),
                  case .message(let message)? = model.item(for: answerID),
                  message.role == .assistant,
                  message.systemStyle == nil,
                  let source = cell.makeAnswerMorphSource(in: window) else { continue }
            return (source, answerID)
        }
        return nil
    }

    /// Starts the morph of the typing row of `source`, taken in the window, into the answer's bubble. The row's place on
    /// screen comes into the list as it stands now, after the pass's changes to the list's rows and scroll position.
    private func startTypingAnswerMorph(_ source: AgentTypingRowSource, answerID: AgentItemID) {
        typingAnswerMorph?.cancel()
        typingAnswerMorph = nil
        guard let window = view.window, let indexPath = messageIndexPath(for: answerID),
              let cell = collectionView.cellForItem(at: indexPath) as? AgentMessageCell else { return }
        cell.layoutIfNeeded()
        typingAnswerMorph = AgentTypingAnswerMorph.start(
            from: source.converted(from: window, to: collectionView),
            into: cell.bubbleBackgroundView,
            in: collectionView
        )
    }

    private func appendedUserMessageID() -> AgentItemID? {
        let itemIDs = model.itemIDs
        guard let lastItemID = itemIDs.last,
              case .message(let message)? = model.item(for: lastItemID),
              message.role == .user else { return nil }
        // Compared by messages, since the list also holds rows of its own, such as the unread divider
        let shownItemIDs = snapshotMessageIDs()
        guard let lastShownItemID = shownItemIDs.last else {
            return model.pendingRevealUserMessageID == lastItemID ? lastItemID : nil
        }
        guard itemIDs.count > shownItemIDs.count,
              itemIDs[shownItemIDs.count - 1] == lastShownItemID else { return nil }
        return lastItemID
    }

    func agentModelDidUpdateItems(_ ids: [AgentItemID], animated: Bool, scrollToBottom: Bool) {
        // Updated items are messages, so they can only end the glow by replacing its typing indicator. Looking for one
        // while there is none would read the whole conversation on every streamed chunk.
        defer {
            if thinkingGlowView.isGlowing { updateThinkingGlow() }
        }
        updateStreamingState(for: ids)
        let hasChangedNewsPostCells = renderedNewsPostItemIDs != currentNewsPostItemIDs
        let isStreamingUpdate = ids.contains { streamingItemIDs.contains($0) }
        if !hasChangedNewsPostCells, isStreamingUpdate, ids.count == 1, let itemID = ids.first,
           let indexPath = messageIndexPath(for: itemID) {
            if collectionView.indexPathsForVisibleItems.contains(indexPath), updateVisibleCell(itemID: itemID) {
                deferredStreamingItemIDs.remove(itemID)
            } else {
                // A prefetched cell can survive offscreen; refresh it when it is actually displayed.
                deferredStreamingItemIDs.insert(itemID)
            }
            // The reveal callback resizes the row when its displayed size changes, independently of network chunks.
            return
        }
        deferredStreamingItemIDs.subtract(ids)
        let isStreamingFinalize = ids.contains { itemID in
            guard let item = model.item(for: itemID),
                  case .message(let message) = item else {
                return false
            }
            return message.role == .assistant && !message.isStreaming
        }
        let preservesBottomAfterFinalResize = isStreamingFinalize
            && pinnedUserMessageID == nil
            && !hasActiveStreamingMessage
            && isNearBottom()
        // An answer that ends, as a Stop ends it while it writes, can change its height over the questions that wait
        let waitingRowMinYs = isStreamingFinalize ? getWaitingRowScreenMinYs() : [:]

        if !hasChangedNewsPostCells,
           (isStreamingUpdate || isStreamingFinalize),
           ids.count == 1,
           let itemID = ids.first,
           updateVisibleCell(itemID: itemID) {
            resizeStreamingRow()
            moveWaitingRows(from: waitingRowMinYs)
            if preservesBottomAfterFinalResize {
                revealLastItemIfNeeded(animated: !isRevealingStreamedText(itemID: itemID))
            }
            updateScrollToBottomButtonVisibility(animated: true)
            return
        }

        let shouldFollowLatest = model.isSupportActive && pinnedUserMessageID == nil && isNearBottom()
        let existingIDs = Set(snapshotMessageIDs())
        let idsToUpdate = ids.filter { existingIDs.contains($0) }
        var snapshot = dataSource.snapshot()
        let reloadedItems = reloadChangedNewsPostCells(in: &snapshot)
        let idsToReconfigure = idsToUpdate.filter { !reloadedItems.contains(.message($0)) }
        guard !idsToReconfigure.isEmpty || !reloadedItems.isEmpty else { return }
        snapshot.reconfigureItems(idsToReconfigure.map { .message($0) })
        dataSource.apply(snapshot, animatingDifferences: animated) { [weak self] in
            guard let self else { return }
            if isStreamingUpdate || self.hasActiveStreamingMessage || isStreamingFinalize {
                self.resizeStreamingRow()
            }
            if preservesBottomAfterFinalResize {
                self.revealLastItemIfNeeded(animated: !idsToUpdate.contains { self.isRevealingStreamedText(itemID: $0) })
            }
            if !isStreamingUpdate && !isStreamingFinalize && !self.hasActiveStreamingMessage {
                self.trimReserveSpacerPreservingOffset()
            }
            if shouldFollowLatest {
                self.followLatestInSupport(isSent: false)
            }
            self.updateScrollToBottomButtonVisibility(animated: true)
        }
    }

    func agentModelDidUpdateHints(animated: Bool) {
        updateHintsView(animated: animated)
    }

    func updateThinkingGlow() {
        thinkingGlowView.setGlowing(thinkingTypingIndicatorID != nil && view.window != nil)
        updateLargeTopState()
    }

    func agentModelDidUpdateState() {
        leaveEditingOnceSupportHasChat()
        updateSupportFollowState()
        loadingOlderIndicator.setLoading(model.isLoadingOlderMessages)
        updateLoadError()
        updatePostSkeleton()
        updateThinkingGlow()
        refreshNavigationTitle(animated: true)
        updateComposerPlaceholder()
        updateSendButtonState()
        refreshNavigationItemMenu()
        updateSupportHint()
        updateOpeningConsentView()
        updateVisibleTypingIndicator()
        updateAccessibilityStatus()
    }

    /// The typing row kept for its top's knock: its top shrinks back, the row then blurs away as it came in, or fades
    /// with Reduce Motion, and leaves the list without moving the rows above it
    func agentModelWillRemoveHeldTypingIndicator(_ id: AgentItemID, then completion: @escaping () -> Void) {
        let finish: () -> Void = { [weak self] in
            guard let self else { return }
            if model.heldTypingIndicatorID == id, let indexPath = messageIndexPath(for: id) {
                reserveSpaceForLeavingRow(at: indexPath)
            }
            animatesNextTimelineReload = true
            completion()
            animatesNextTimelineReload = false
        }
        guard view.window != nil, UIView.areAnimationsEnabled, let cell = typingIndicatorCell(for: id) else {
            finish()
            return
        }
        let isMotionReduced = UIAccessibility.isReduceMotionEnabled
        guard !isMotionReduced else {
            AgentBlurTransition.animateOut(
                cell.contentView.layer,
                duration: Self.stoppedTypingRowExitDuration,
                shouldSkipBlur: true,
                completion: finish
            )
            return
        }
        cell.releaseTop()
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.stoppedTypingTopShrinkDuration) { [weak self] in
            // A new question meanwhile took the row away already
            guard let self, model.heldTypingIndicatorID == id else { return }
            guard view.window != nil, let cell = typingIndicatorCell(for: id) else {
                finish()
                return
            }
            cell.fadeAway(duration: Self.stoppedTypingRowExitDuration, completion: finish)
        }
    }

    func agentModelWillRevealSentUserMessage(_ userMessageID: AgentItemID, then completion: @escaping () -> Void) {
        // The scroll-to-bottom button's signal, read before the scroll to the latest row stops, which counts as being
        // at the chat's end
        let isFollowingChatEnd = isNearBottom()
        if model.isSupportActive {
            pendingSentSource = nil
            pendingSentTextPicture = nil
            pinnedUserMessageID = nil
            // A question that waited is already in the chat, which follows it only from the chat's end
            guard model.revealingWaitingMessageID != userMessageID || isFollowingChatEnd else {
                completion()
                return
            }
            followLatestInSupport(isSent: true, then: completion)
            return
        }
        collectionView.isScrollingToLatest = false
        isRevealingSentUserMessage = true
        pinnedUserMessageID = userMessageID
        let finish: () -> Void = { [weak self] in
            self?.isRevealingSentUserMessage = false
            completion()
        }

        collectionView.layoutIfNeeded()
        // A question that waited goes once the answer before it ends: its bubble is already in the chat, which brings
        // it up as it does a question just sent while the user follows the chat's end. Scrolled away from the end, the
        // chat stays where it is. The question is pinned all the same, so what comes under it keeps the rows on screen
        // in place rather than taking the chat down.
        if model.revealingWaitingMessageID == userMessageID {
            revealsSentMessageFromBottom = false
            guard isFollowingChatEnd else {
                finish()
                return
            }
            bringSentUserMessageUp(userMessageID, isShownInPlace: true, then: finish)
            return
        }
        // A question that left the field, or a tapped suggestion, turns into its bubble as Telegram's send does
        let source = takeSentSource()
        let textPicture = takeSentTextPicture()
        let isFirstQuestion = dateHeaderID(for: userMessageID).map { $0 == model.itemIDs.first } ?? false
        // At the chat's end, a question that lands under what shows, as in a chat opened at its end, comes into sight
        // there as the chat's end follows it
        let roomOffsetY = revealsSentMessageFromBottom && !isFirstQuestion
            && getSentRowsShownInPlace(for: userMessageID) == nil
            ? getOffsetYShowingSentUserMessage(userMessageID, occlusionBottomInset: occlusionBottomInset)
            : nil
        if revealsSentMessageFromBottom,
           let rows = getSentRowsShownInPlace(for: userMessageID, atOffsetY: roomOffsetY) {
            // As on Android, the question first appears where it lands, as a suggestion's question takes the
            // suggestions' place, and the chat brings it up a moment later
            revealsSentMessageFromBottom = false
            if roomOffsetY != nil {
                makeRoom(forSentUserMessage: userMessageID)
            }
            let suggestionMorph = source.flatMap { startSuggestionMorph(from: $0, to: userMessageID) }
            let appearanceDuration: TimeInterval
            if UIAccessibility.isReduceMotionEnabled {
                appearanceDuration = 0
            } else if suggestionMorph != nil {
                appearanceDuration = AgentSuggestionMorph.duration
            } else if source != nil {
                appearanceDuration = AgentSentMessageMorph.duration
            } else {
                appearanceDuration = AgentSentMessageAppearance.duration
            }
            if appearanceDuration > 0 {
                for cell in rows.compactMap(collectionView.cellForItem(at:)) {
                    let messageCell = cell as? AgentMessageCell
                    if let messageCell, messageCell.messageID == userMessageID {
                        // The suggestion's morph shows the bubble
                        if suggestionMorph != nil { continue }
                        if let source, case .text(let picture) = source.kind {
                            AgentSentMessageMorph.animate(
                                messageCell.sentAppearanceView,
                                target: messageCell.sentTextView,
                                from: picture,
                                at: source.frame,
                                in: view
                            )
                            continue
                        }
                    }
                    AgentSentMessageAppearance.animate(messageCell?.sentAppearanceView ?? cell.contentView)
                }
            }
            let delay = appearanceDuration + AgentVCLayout.sentUserMessagePinDelay
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return completion() }
                self.bringSentUserMessageUp(userMessageID, isShownInPlace: true, then: finish)
            }
            return
        }

        if roomOffsetY != nil {
            revealLastItemSettlingRowHeights()
        }
        revealsSentMessageFromBottom = false
        // A tapped suggestion turns into its question's bubble also where the chat brings the question up from below,
        // following it as the chat scrolls, and so does a question that left the field, its text flying out of it on
        // Telegram iOS's 0.4 s
        let isMorphing: Bool
        if let source, case .text = source.kind {
            isMorphing = textPicture.flatMap {
                startSuggestionMorph(from: $0, to: userMessageID, duration: AgentSentMessageMorph.duration)
            } != nil
        } else {
            isMorphing = source.flatMap { startSuggestionMorph(from: $0, to: userMessageID) } != nil
        }
        if !isMorphing {
            revealSentMessageWithoutMorph(userMessageID)
        }
        bringSentUserMessageUp(userMessageID, isShownInPlace: isMorphing, then: finish)
    }

    /// A question sent while an answer is written, or before its discussion's thread exists, turns into its bubble at the
    /// chat's end, as a question just sent does where it shows. It stays there until the answer ends or the thread
    /// exists, and the question goes. Returns how long it takes to turn into its bubble.
    private func startWaitingUserMessageAppearance(_ userMessageID: AgentItemID) -> TimeInterval {
        let source = takeSentSource()
        guard UIView.areAnimationsEnabled, !UIAccessibility.isReduceMotionEnabled,
              let indexPath = messageIndexPath(for: userMessageID),
              let cell = collectionView.cellForItem(at: indexPath) as? AgentMessageCell,
              cell.messageID == userMessageID else { return 0 }
        cell.layoutIfNeeded()
        if let source, case .text(let picture) = source.kind {
            AgentSentMessageMorph.animate(
                cell.sentAppearanceView,
                target: cell.sentTextView,
                from: picture,
                at: source.frame,
                in: view
            )
            return AgentSentMessageMorph.duration
        }
        // A tapped suggestion turns into the bubble, as it does for a question that goes at once
        if let source, case .suggestion = source.kind, startSuggestionMorph(from: source, to: userMessageID) != nil {
            return AgentSuggestionMorph.duration
        }
        AgentSentMessageAppearance.animate(cell.sentAppearanceView)
        return AgentSentMessageAppearance.duration
    }

    /// Once the waiting question has turned into its bubble, after `delay`, the chat follows it down when it was at its
    /// end
    private func followWaitingUserMessage(after delay: TimeInterval, followsChatEnd: Bool) {
        // After the pass that keeps the chat's rows in place, which would take a scroll in it back
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            if followsChatEnd {
                revealLastItemIfNeeded(animated: true)
            }
            updateScrollToBottomButtonVisibility(animated: true)
        }
    }

    private func startSuggestionMorph(
        from source: AgentSentMessageSource,
        to userMessageID: AgentItemID,
        duration: CFTimeInterval = AgentSuggestionMorph.duration
    ) -> AgentSuggestionMorph? {
        suggestionMorph?.cancel()
        suggestionMorph = AgentSuggestionMorph.start(from: source, in: view, duration: duration) { [weak self] in
            guard let self, let indexPath = self.messageIndexPath(for: userMessageID),
                  let cell = self.collectionView.cellForItem(at: indexPath) as? AgentMessageCell,
                  cell.messageID == userMessageID else { return nil }
            return cell
        }
        return suggestionMorph
    }

    /// The source of the question just sent, if it is recent enough to be this question's
    private func takeSentSource() -> AgentSentMessageSource? {
        defer { pendingSentSource = nil }
        guard let source = pendingSentSource,
              CACurrentMediaTime() - source.time < AgentSentMessageSource.lifetime else { return nil }
        return source
    }

    /// A question with nothing to come out of, as one of more than ten lines, fades in and grows into its bubble as the
    /// chat brings it up, as Android's row opens and as it does where it lands on screen: at once if the chat shows its
    /// row, or as the row comes on screen
    private func revealSentMessageWithoutMorph(_ userMessageID: AgentItemID) {
        pendingSentAppearanceID = nil
        guard view.window != nil, UIView.areAnimationsEnabled, !UIAccessibility.isReduceMotionEnabled else { return }
        if let indexPath = messageIndexPath(for: userMessageID),
           let cell = collectionView.cellForItem(at: indexPath) as? AgentMessageCell, cell.messageID == userMessageID {
            AgentSentMessageAppearance.animate(cell.sentAppearanceView)
        } else {
            pendingSentAppearanceID = userMessageID
        }
    }

    /// The field's text of the question just sent, drawn from its layers, if it is recent enough to be this question's
    private func takeSentTextPicture() -> AgentSentMessageSource? {
        defer { pendingSentTextPicture = nil }
        guard let source = pendingSentTextPicture,
              CACurrentMediaTime() - source.time < AgentSentMessageSource.lifetime else { return nil }
        return source
    }

    /// The rows a sent question adds, itself and a date line over it, when they show whole on screen right under a row
    /// that is on screen too, with the list at `offsetY`, or where it stands
    private func getSentRowsShownInPlace(
        for userMessageID: AgentItemID,
        atOffsetY offsetY: CGFloat? = nil
    ) -> [IndexPath]? {
        guard let indexPath = messageIndexPath(for: userMessageID) else { return nil }
        let firstIndexPath = dateHeaderID(for: userMessageID).flatMap(messageIndexPath(for:)) ?? indexPath
        guard firstIndexPath.item > 0,
              let previousFrame = collectionView.layoutAttributesForItem(
                  at: IndexPath(item: firstIndexPath.item - 1, section: firstIndexPath.section)
              )?.frame,
              let frame = collectionView.layoutAttributesForItem(at: indexPath)?.frame else { return nil }
        let currentOffsetY = collectionView.contentOffset.y
        let visible = visibleContentRect().offsetBy(dx: 0, dy: (offsetY ?? currentOffsetY) - currentOffsetY)
        guard previousFrame.maxY > visible.minY, previousFrame.minY < visible.maxY,
              frame.maxY <= visible.maxY + 0.5 else { return nil }
        return (firstIndexPath.item...indexPath.item).map { IndexPath(item: $0, section: indexPath.section) }
    }

    /// Where the list shows the sent question's bottom just above `occlusion`, the height covering the list's bottom,
    /// as the chat's end shows its last row
    private func getOffsetYShowingSentUserMessage(
        _ userMessageID: AgentItemID,
        occlusionBottomInset occlusion: CGFloat
    ) -> CGFloat? {
        guard let indexPath = messageIndexPath(for: userMessageID),
              let frame = collectionView.layoutAttributesForItem(at: indexPath)?.frame else { return nil }
        return clampedContentOffsetY(frame.maxY - collectionView.bounds.height + occlusion)
    }

    /// Scrolls the list up on the chat's list spring until the sent question shows whole above the field, as its text
    /// flies into its bubble, which follows it there. The question stops above the field as it stood when the question
    /// came: the keyboard the question closes meanwhile leaves the rows of a question about to be brought up in place.
    /// The scroll counts as one to the chat's end, so the scroll-to-bottom button stays away. With Reduce Motion or
    /// animations off the list is there at once.
    private func makeRoom(forSentUserMessage userMessageID: AgentItemID) {
        guard UIView.areAnimationsEnabled, !UIAccessibility.isReduceMotionEnabled, view.window != nil else {
            revealLastItemSettlingRowHeights()
            return
        }
        let occlusion = occlusionBottomInset
        collectionView.isScrollingToLatest = true
        listScrollAnimator.scroll(to: { [weak self] in
            self?.getOffsetYShowingSentUserMessage(userMessageID, occlusionBottomInset: occlusion)
        }) { [weak self] _ in
            self?.collectionView.isScrollingToLatest = false
        }
    }

    /// Scrolls the sent question to where it stays while its answer comes, or brings it in from below when the chat
    /// is there already and the question has not appeared yet
    private func bringSentUserMessageUp(
        _ userMessageID: AgentItemID,
        isShownInPlace: Bool,
        then finish: @escaping () -> Void
    ) {
        // A scroll that made room for the question at the chat's end goes on to its place here
        collectionView.isScrollingToLatest = false
        applyMinimalArrivalReserveSpacerHeight(for: userMessageID)
        collectionView.layoutIfNeeded()
        guard let indexPath = messageIndexPath(for: userMessageID),
              let targetOffsetY = pinnedOffsetY(for: userMessageID) else {
            staggerTypingIndicatorReveal(then: finish)
            return
        }
        let clampedOffsetY = clampedContentOffsetY(targetOffsetY)

        guard abs(clampedOffsetY - collectionView.contentOffset.y) > 0.5 else {
            if isShownInPlace {
                finish()
            } else {
                animateSentUserMessageFlyUp(at: indexPath, then: finish)
            }
            return
        }

        listScrollAnimator.scroll(to: { [weak self] in
            guard let self, let offsetY = self.pinnedOffsetY(for: userMessageID) else { return nil }
            return self.clampedContentOffsetY(offsetY)
        }) { _ in
            finish()
        }
    }

    private func animateSentUserMessageFlyUp(at indexPath: IndexPath, then completion: @escaping () -> Void) {
        guard let cell = collectionView.cellForItem(at: indexPath),
              let attributes = collectionView.layoutAttributesForItem(at: indexPath) else {
            staggerTypingIndicatorReveal(then: completion)
            return
        }
        let visible = visibleContentRect()
        let startTranslation = max(0, visible.maxY - attributes.frame.minY)
        guard startTranslation > 1 else {
            staggerTypingIndicatorReveal(then: completion)
            return
        }
        cell.transform = CGAffineTransform(translationX: 0, y: startTranslation)
        cell.alpha = 0
        UIView.animate(
            withDuration: AgentVCLayout.sentUserMessageFlyUpDuration,
            delay: 0,
            options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction]
        ) {
            cell.transform = .identity
            cell.alpha = 1
        } completion: { _ in
            cell.transform = .identity
            cell.alpha = 1
            completion()
        }
    }

    private func staggerTypingIndicatorReveal(then completion: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + AgentVCLayout.typingIndicatorRevealGap) {
            completion()
        }
    }
}
