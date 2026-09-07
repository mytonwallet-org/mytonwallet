import UIKit
import WalletCore
import WReachability
import Perception

public enum WalletUpdateStatus: Equatable {
    case waitingForNetwork
    case updating
    case updated
}

@Perceptible
@MainActor
public final class WalletUpdateStatusModel: WalletCoreData.EventsObserver {
    public static let shared = WalletUpdateStatusModel()

    public private(set) var state: WalletUpdateStatus = .updated

    @PerceptionIgnored private let reachability = Reachability()
    @PerceptionIgnored private var updatingTask: Task<Void, Never>?

    private init() {
        reachability.whenReachable = { [weak self] _ in self?.updateStatus() }
        reachability.whenUnreachable = { [weak self] _ in self?.updateStatus() }
        reachability.startNotifier()
        WalletCoreData.add(eventObserver: self)
        updateStatus()
    }

    public func walletCore(event: WalletCoreData.Event) {
        switch event {
        case .updatingStatusChanged, .applicationWillEnterForeground:
            updateStatus()
        case .accountChanged:
            cancelUpdatingTask()
            state = reachability.connection == .unavailable ? .waitingForNetwork : .updated
            updateStatus()
        default:
            break
        }
    }

    private func updateStatus() {
        guard reachability.connection != .unavailable else {
            cancelUpdatingTask()
            state = .waitingForNetwork
            return
        }
        guard AccountStore.updatingActivities || AccountStore.updatingBalance else {
            cancelUpdatingTask()
            state = .updated
            return
        }
        if state == .waitingForNetwork {
            cancelUpdatingTask()
            state = .updating
        } else if state != .updating, updatingTask == nil {
            updatingTask = Task { [weak self] in
                do {
                    try await Task.sleep(for: .seconds(2))
                } catch {
                    return
                }
                guard let self else { return }
                updatingTask = nil
                if reachability.connection == .unavailable {
                    state = .waitingForNetwork
                } else {
                    state = AccountStore.updatingActivities || AccountStore.updatingBalance ? .updating : .updated
                }
            }
        }
    }

    private func cancelUpdatingTask() {
        updatingTask?.cancel()
        updatingTask = nil
    }
}
