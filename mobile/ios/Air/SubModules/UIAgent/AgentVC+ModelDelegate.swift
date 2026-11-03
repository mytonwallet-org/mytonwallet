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
        let crossfade = hasStreaming
        var didRemoveInitialOpeningInput = false
        if let pinnedUserMessageID, !model.itemIDs.contains(pinnedUserMessageID) {
            didRemoveInitialOpeningInput = pinnedUserMessageID == initialOpeningInputItemID
            self.pinnedUserMessageID = nil
        }
        let sentUserMessageID = hasStreaming ? nil : appendedUserMessageID()
        revealsSentMessageFromBottom = sentUserMessageID != nil && lastKnownNearBottom
        if let sentUserMessageID {
            pinnedUserMessageID = sentUserMessageID
        }

        let didApplyTimeline: () -> Void = { [weak self] in
            guard let self else { return }
            self.collectionView.layoutIfNeeded()

            if didRemoveInitialOpeningInput {
                self.hasPerformedInitialScroll = false
            }
            self.performInitialScrollIfNeeded()

            if hasStreaming {
                self.resizeStreamingRow()
                return
            }

            if self.lastTypingIndicatorID != nil {
                self.revealTypingIndicatorIfNeeded()
            } else {
                self.trimReserveSpacerPreservingOffset()
            }
            self.lastKnownNearBottom = self.isNearBottom()
            self.updateScrollToBottomButtonVisibility(animated: false)
        }
        let applyTimeline = {
            self.applySnapshot(
                animated: false,
                reconfigureItemIDs: reconfigureItemIDs,
                crossfade: crossfade,
                completion: didApplyTimeline
            )
        }
        if pinnedUserMessageID != nil {
            let dateAnchor = previousDateAnchor.flatMap {
                $0.itemID == pinnedUserMessageID && dateHeaderID(for: $0.itemID) != nil ? $0 : nil
            }
            preservingTopVisibleRow(anchor: dateAnchor, fittingReserveSpacer: true, applyTimeline)
        } else {
            applyTimeline()
        }
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

        if !hasChangedNewsPostCells,
           (isStreamingUpdate || isStreamingFinalize),
           ids.count == 1,
           let itemID = ids.first,
           updateVisibleCell(itemID: itemID) {
            resizeStreamingRow()
            if preservesBottomAfterFinalResize {
                revealLastItemIfNeeded(animated: !isRevealingStreamedText(itemID: itemID))
            }
            updateScrollToBottomButtonVisibility(animated: true)
            return
        }

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
            self.updateScrollToBottomButtonVisibility(animated: true)
        }
    }

    func agentModelDidUpdateHints(animated: Bool) {
        updateHintsView(animated: animated)
    }

    func updateThinkingGlow() {
        thinkingGlowView.setGlowing(lastTypingIndicatorID != nil && view.window != nil)
    }

    func agentModelDidUpdateState() {
        loadingOlderIndicator.setLoading(model.isLoadingOlderMessages)
        updateLoadError()
        updateThinkingGlow()
        refreshNavigationTitle(animated: true)
        updateComposerPlaceholder()
        updateSendButtonState()
        refreshNavigationItemMenu()
        updateOpeningConsentView()
        updateVisibleTypingIndicator()
        updateAccessibilityStatus()
    }

    func agentModelWillRevealSentUserMessage(_ userMessageID: AgentItemID, then completion: @escaping () -> Void) {
        collectionView.isScrollingToLatest = false
        isRevealingSentUserMessage = true
        pinnedUserMessageID = userMessageID
        let finish: () -> Void = { [weak self] in
            self?.isRevealingSentUserMessage = false
            completion()
        }

        let isFirstQuestion = dateHeaderID(for: userMessageID).map { $0 == model.itemIDs.first } ?? false
        if revealsSentMessageFromBottom && !isFirstQuestion {
            revealLastItemSettlingRowHeights()
        } else {
            collectionView.layoutIfNeeded()
        }
        revealsSentMessageFromBottom = false
        applyMinimalArrivalReserveSpacerHeight(for: userMessageID)
        collectionView.layoutIfNeeded()
        guard let indexPath = messageIndexPath(for: userMessageID),
              let targetOffsetY = pinnedOffsetY(for: userMessageID) else {
            staggerTypingIndicatorReveal(then: finish)
            return
        }
        let clampedOffsetY = clampedContentOffsetY(targetOffsetY)

        guard abs(clampedOffsetY - collectionView.contentOffset.y) > 0.5 else {
            animateSentUserMessageFlyUp(at: indexPath, then: finish)
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
