import WalletCore

/// Stores messages hidden during editing or regeneration and edited message text.
struct AgentV2MessageReplacement {
    /// The presentation update needed after a run ends.
    enum Resolution: Equatable {
        /// Keeps the current message presentation.
        case none
        /// Shows the hidden messages again.
        case restore
        /// Shows the hidden messages and reloads the thread from the server because it has admitted the run.
        case restoreAndResync
    }

    private struct PendingEdit {
        var targetNativeID: String
        var isAdmitted: Bool
    }

    /// An answer asked for again: it and the messages after it stay out of the chat while the new answer is written in
    /// their place, and come back if the server turns the request down
    private struct PendingRegeneration {
        let targetNativeID: String
        var isAdmitted: Bool
    }

    private(set) var ignoredNativeIDs = Set<String>()
    private(set) var editedTextByNativeID: [String: String] = [:]
    private var pendingEdit: PendingEdit?
    private var pendingRegeneration: PendingRegeneration?

    mutating func beginEditing(targetNativeID: String, messages: [AgentV2NativeMessage]) {
        guard let index = messages.firstIndex(where: { $0.id == targetNativeID }) else { return }
        ignoredNativeIDs = Set(messages.suffix(from: index + 1).map(\.id))
        pendingEdit = PendingEdit(targetNativeID: targetNativeID, isAdmitted: false)
    }

    mutating func sendEdit(targetNativeID: String, text: String) {
        editedTextByNativeID[targetNativeID] = text
        pendingEdit = PendingEdit(targetNativeID: targetNativeID, isAdmitted: false)
    }

    mutating func beginRegeneration(targetNativeID: String, replacedNativeIDs: [String]) {
        ignoredNativeIDs = Set(replacedNativeIDs)
        pendingRegeneration = PendingRegeneration(targetNativeID: targetNativeID, isAdmitted: false)
    }

    mutating func admitRegeneration(runID: String?) {
        guard var pendingRegeneration, !pendingRegeneration.isAdmitted, runID != nil else { return }
        pendingRegeneration.isAdmitted = true
        self.pendingRegeneration = pendingRegeneration
    }

    mutating func reconcileMessageID(localID: String, canonicalID: String) {
        guard localID != canonicalID else { return }
        if var pendingEdit, pendingEdit.targetNativeID == localID {
            pendingEdit.targetNativeID = canonicalID
            pendingEdit.isAdmitted = true
            self.pendingEdit = pendingEdit
        }
        if let editedText = editedTextByNativeID.removeValue(forKey: localID) {
            editedTextByNativeID[canonicalID] = editedText
        }
    }

    mutating func runTerminated(outcome: ApiAgentV2RunResultState?) -> Resolution {
        guard let outcome, outcome != .completed else { return .none }
        if let pendingEdit, !pendingEdit.isAdmitted {
            ignoredNativeIDs.removeAll()
            editedTextByNativeID.removeAll()
            self.pendingEdit = nil
            return .restore
        }
        return restoreRegeneration()
    }

    mutating func regenerationDidNotStart() -> Resolution {
        restoreRegeneration()
    }

    private mutating func restoreRegeneration() -> Resolution {
        guard let pendingRegeneration else { return .none }
        ignoredNativeIDs.removeAll()
        self.pendingRegeneration = nil
        return pendingRegeneration.isAdmitted ? .restoreAndResync : .restore
    }

    mutating func prune(messages: [AgentV2NativeMessage]) {
        let currentIDs = Set(messages.map(\.id))
        if ignoredNativeIDs.isDisjoint(with: currentIDs) {
            ignoredNativeIDs.removeAll()
        }
        editedTextByNativeID = editedTextByNativeID.filter { nativeID, text in
            guard let message = messages.first(where: { $0.id == nativeID }) else { return false }
            return message.text != text
        }
        if ignoredNativeIDs.isEmpty && editedTextByNativeID.isEmpty {
            pendingEdit = nil
            pendingRegeneration = nil
        }
    }

    mutating func reset() {
        ignoredNativeIDs.removeAll()
        editedTextByNativeID.removeAll()
        pendingEdit = nil
        pendingRegeneration = nil
    }

    func seenMessageCount(_ count: Int?, messages: [AgentV2NativeMessage]) -> Int? {
        guard let count else { return nil }
        return count - messages.filter {
            ignoredNativeIDs.contains($0.id) && $0.role != .event && !$0.status.isStreaming
        }.count
    }
}
