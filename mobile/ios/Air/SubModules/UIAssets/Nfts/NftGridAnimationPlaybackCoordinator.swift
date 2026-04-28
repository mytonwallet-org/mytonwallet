import Foundation
import QuartzCore

@MainActor
final class NftGridAnimationPlaybackCoordinator {
    struct Configuration: Equatable, Sendable {
        var averageAnimationDuration: TimeInterval
        var staggerWindowFraction: Double
        var staggerDelayDecay: Double
        var incomingBatchCoalescingDelay: TimeInterval
        var minimumInterItemDelay: TimeInterval
        var maximumLeadingInterItemDelay: TimeInterval
        var renderingConfiguration: NftMediaView.AnimationRenderingConfiguration

        static let nftGridDefault = Self(
            averageAnimationDuration: 3.0,
            staggerWindowFraction: 0.45,
            staggerDelayDecay: 0.7,
            incomingBatchCoalescingDelay: 0.04,
            minimumInterItemDelay: 0.08,
            maximumLeadingInterItemDelay: 0.35,
            renderingConfiguration: .nftGridDefault
        )
    }

    struct VisibleItem {
        let id: String
        weak var cell: NftCell?
    }

    private struct PendingEntry {
        let id: String
        let scheduledStartTime: CFTimeInterval
        let delayFromPrevious: TimeInterval
    }

    var configuration: Configuration

    private var isActive = false
    private var activationSessionID: UInt64 = 0
    private var visibleItemsByID: [String: VisibleItem] = [:]
    private var visibleItemOrder: [String] = []
    private var pendingQueue: [PendingEntry] = []
    private var unscheduledIDs: [String] = []
    private var playedVisibleIDs = Set<String>()
    private var scheduledTasks: [String: Task<Void, Never>] = [:]
    private var schedulingPassTask: Task<Void, Never>?

    init(configuration: Configuration = .nftGridDefault) {
        self.configuration = configuration
    }

    func setActive(_ isActive: Bool) {
        guard self.isActive != isActive else {
            return
        }

        self.isActive = isActive
        self.activationSessionID &+= 1
        self.cancelSchedulingPass()
        self.cancelAllScheduledTasks()
        self.stopPlaybackForVisibleItems()
        self.pendingQueue.removeAll()
        self.unscheduledIDs.removeAll()
        self.playedVisibleIDs.removeAll()

        guard isActive else {
            return
        }

        self.unscheduledIDs = self.visibleItemOrder
        self.requestSchedulingPass(activationSessionID: self.activationSessionID)
    }

    func updateVisibleItems(_ visibleItems: [VisibleItem]) {
        let updatedVisibleItemsByID = Dictionary(uniqueKeysWithValues: visibleItems.map { ($0.id, $0) })
        let updatedVisibleItemOrder = visibleItems.map(\.id)
        var needsSchedulingPass = false
        var didRemovePendingEntries = false

        let removedIDs = Set(self.visibleItemsByID.keys).subtracting(updatedVisibleItemsByID.keys)
        for removedID in removedIDs {
            self.cancelScheduledTask(for: removedID)
            self.visibleItemsByID[removedID]?.cell?.stopAnimationPlayback()
            self.visibleItemsByID.removeValue(forKey: removedID)
            self.playedVisibleIDs.remove(removedID)
            let pendingCount = self.pendingQueue.count
            self.pendingQueue.removeAll { $0.id == removedID }
            didRemovePendingEntries = didRemovePendingEntries || self.pendingQueue.count != pendingCount
            self.unscheduledIDs.removeAll { $0 == removedID }
        }

        for visibleItem in visibleItems {
            defer {
                self.visibleItemsByID[visibleItem.id] = visibleItem
            }

            guard self.visibleItemsByID[visibleItem.id] == nil else {
                continue
            }
            guard self.isActive else {
                continue
            }
            guard !self.playedVisibleIDs.contains(visibleItem.id),
                  !self.pendingQueue.contains(where: { $0.id == visibleItem.id }),
                  !self.unscheduledIDs.contains(visibleItem.id) else {
                continue
            }

            self.unscheduledIDs.append(visibleItem.id)
            needsSchedulingPass = true
        }

        if didRemovePendingEntries, self.isActive {
            self.reschedulePendingQueue(activationSessionID: self.activationSessionID)
        }

        if needsSchedulingPass {
            self.requestSchedulingPass(activationSessionID: self.activationSessionID)
        }

        self.visibleItemOrder = updatedVisibleItemOrder
    }

    private func requestSchedulingPass(activationSessionID: UInt64) {
        guard self.isActive, !self.unscheduledIDs.isEmpty else {
            return
        }
        guard self.schedulingPassTask == nil else {
            return
        }

        let delay = self.configuration.incomingBatchCoalescingDelay
        self.schedulingPassTask = Task { [weak self] in
            guard let self else {
                return
            }

            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }

            guard !Task.isCancelled else {
                return
            }

            self.schedulingPassTask = nil
            self.scheduleUnscheduledItems(activationSessionID: activationSessionID)
        }
    }

    private func scheduleUnscheduledItems(activationSessionID: UInt64) {
        guard self.isActive, self.activationSessionID == activationSessionID else {
            return
        }

        let batchIDs = self.unscheduledIDs.filter { id in
            self.visibleItemsByID[id] != nil &&
                !self.playedVisibleIDs.contains(id) &&
                !self.pendingQueue.contains(where: { $0.id == id })
        }
        self.unscheduledIDs.removeAll()

        guard !batchIDs.isEmpty else {
            return
        }

        if self.pendingQueue.isEmpty {
            self.scheduleInitialBatch(batchIDs, activationSessionID: activationSessionID)
        } else {
            self.scheduleAppendedBatch(batchIDs, activationSessionID: activationSessionID)
        }
    }

    private func scheduleInitialBatch(_ ids: [String], activationSessionID: UInt64) {
        let now = CACurrentMediaTime()
        let delays = self.makeNormalizedBatchDelays(count: ids.count)

        for (index, id) in ids.enumerated() {
            let cumulativeDelay = delays[index]
            let delayFromPrevious = index == 0 ? cumulativeDelay : cumulativeDelay - delays[index - 1]
            let entry = PendingEntry(
                id: id,
                scheduledStartTime: now + cumulativeDelay,
                delayFromPrevious: delayFromPrevious
            )
            self.pendingQueue.append(entry)
            self.schedulePendingEntry(entry, activationSessionID: activationSessionID)
        }
    }

    private func scheduleAppendedBatch(_ ids: [String], activationSessionID: UInt64) {
        guard let tail = self.pendingQueue.last else {
            self.scheduleInitialBatch(ids, activationSessionID: activationSessionID)
            return
        }

        let now = CACurrentMediaTime()
        let appendedDelays = self.makeNormalizedBatchDelays(count: ids.count + 1)
        var previousStartTime = tail.scheduledStartTime
        var previousDelay = max(
            self.configuration.minimumInterItemDelay,
            min(
                max(self.configuration.minimumInterItemDelay, tail.delayFromPrevious),
                max(self.configuration.minimumInterItemDelay, tail.scheduledStartTime - now)
            )
        )

        for index in ids.indices {
            let baseGap = appendedDelays[index + 1] - appendedDelays[index]
            let gap = min(previousDelay, max(self.configuration.minimumInterItemDelay, baseGap))
            let startTime = max(now + self.configuration.minimumInterItemDelay, previousStartTime + gap)
            let entry = PendingEntry(
                id: ids[index],
                scheduledStartTime: startTime,
                delayFromPrevious: gap
            )
            self.pendingQueue.append(entry)
            self.schedulePendingEntry(entry, activationSessionID: activationSessionID)

            previousStartTime = startTime
            previousDelay = gap
        }
    }

    private func reschedulePendingQueue(activationSessionID: UInt64) {
        let pendingIDs = self.pendingQueue.map(\.id)
        guard !pendingIDs.isEmpty else {
            return
        }

        for id in pendingIDs {
            self.cancelScheduledTask(for: id)
        }
        self.pendingQueue.removeAll()
        self.scheduleInitialBatch(pendingIDs, activationSessionID: activationSessionID)
    }

    private func schedulePendingEntry(_ entry: PendingEntry, activationSessionID: UInt64) {
        self.cancelScheduledTask(for: entry.id)
        let delayUntilStart = max(0, entry.scheduledStartTime - CACurrentMediaTime())

        let task = Task { [weak self] in
            guard let self else {
                return
            }

            if delayUntilStart > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delayUntilStart * 1_000_000_000))
            }

            guard !Task.isCancelled else {
                return
            }
            guard self.isActive, self.activationSessionID == activationSessionID else {
                return
            }
            guard let visibleItem = self.visibleItemsByID[entry.id] else {
                self.pendingQueue.removeAll { $0.id == entry.id }
                self.scheduledTasks[entry.id] = nil
                return
            }
            guard let cell = visibleItem.cell, cell.nftId == entry.id else {
                self.pendingQueue.removeAll { $0.id == entry.id }
                self.scheduledTasks[entry.id] = nil
                if !self.playedVisibleIDs.contains(entry.id),
                   !self.pendingQueue.contains(where: { $0.id == entry.id }),
                   !self.unscheduledIDs.contains(entry.id) {
                    self.unscheduledIDs.append(entry.id)
                    self.requestSchedulingPass(activationSessionID: activationSessionID)
                }
                return
            }

            self.pendingQueue.removeAll { $0.id == entry.id }
            self.playedVisibleIDs.insert(entry.id)
            cell.playAnimationOnce(renderingConfiguration: self.configuration.renderingConfiguration)
            self.scheduledTasks[entry.id] = nil
        }
        self.scheduledTasks[entry.id] = task
    }

    private func makeNormalizedBatchDelays(count: Int) -> [TimeInterval] {
        let baseDelays = self.makeStaggeredDelays(count: count)
        guard !baseDelays.isEmpty else {
            return []
        }
        guard baseDelays.count > 1 else {
            return [0]
        }

        var result: [TimeInterval] = [0]
        var previousGap: TimeInterval?

        for index in 1 ..< baseDelays.count {
            let baseGap = baseDelays[index] - baseDelays[index - 1]
            var gap = max(self.configuration.minimumInterItemDelay, baseGap)
            if index == 1 {
                gap = min(self.configuration.maximumLeadingInterItemDelay, gap)
            }
            if let previousGap {
                gap = min(previousGap, gap)
            }
            result.append(result.last! + gap)
            previousGap = gap
        }

        return result
    }

    private func makeStaggeredDelays(count: Int) -> [TimeInterval] {
        guard count > 0 else {
            return []
        }
        guard count > 1 else {
            return [0]
        }

        let totalWindow = max(0, self.configuration.averageAnimationDuration * self.configuration.staggerWindowFraction)
        guard totalWindow > 0 else {
            return Array(repeating: 0, count: count)
        }

        let gapWeights = (0 ..< (count - 1)).map { index in
            pow(self.configuration.staggerDelayDecay, Double(index))
        }
        let totalWeight = gapWeights.reduce(0, +)
        guard totalWeight > 0 else {
            return Array(repeating: 0, count: count)
        }

        var delays: [TimeInterval] = [0]
        var accumulatedDelay: TimeInterval = 0

        for gapWeight in gapWeights {
            accumulatedDelay += totalWindow * gapWeight / totalWeight
            delays.append(accumulatedDelay)
        }

        return delays
    }

    private func stopPlaybackForVisibleItems() {
        for visibleItem in self.visibleItemsByID.values {
            visibleItem.cell?.stopAnimationPlayback()
        }
    }

    private func cancelScheduledTask(for id: String) {
        self.scheduledTasks.removeValue(forKey: id)?.cancel()
    }

    private func cancelSchedulingPass() {
        self.schedulingPassTask?.cancel()
        self.schedulingPassTask = nil
    }

    private func cancelAllScheduledTasks() {
        for task in self.scheduledTasks.values {
            task.cancel()
        }
        self.scheduledTasks.removeAll()
    }
}
