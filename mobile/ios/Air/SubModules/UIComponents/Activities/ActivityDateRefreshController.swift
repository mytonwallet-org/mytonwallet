import UIKit

@MainActor
public protocol ActivityDateDisplaying: AnyObject {
    /// Updates only date text and returns its next time-dependent transition, if any
    @discardableResult func updateDate(relativeTo now: Date) -> Date?
}

@MainActor
public final class ActivityDateRefreshController {
    private weak var collectionView: UICollectionView?
    private let getCurrentDate: () -> Date
    nonisolated(unsafe) private var observers: [NSObjectProtocol] = []
    private var isActive = false
    private var isSuspended = false
    private var updateTask: Task<Void, Never>?
    nonisolated(unsafe) private(set) var timer: Timer?
    private(set) var nextUpdateDate: Date?

    public init(collectionView: UICollectionView, getCurrentDate: @escaping () -> Date = { .now }) {
        self.collectionView = collectionView
        self.getCurrentDate = getCurrentDate
        for name in [UIApplication.significantTimeChangeNotification,
                     NSNotification.Name.NSSystemTimeZoneDidChange, NSLocale.currentLocaleDidChangeNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.cancelUpdates()
                    self?.setNeedsUpdate()
                }
            })
        }
        observers.append(NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isSuspended = false
                self?.setNeedsUpdate()
            }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isSuspended = true
                self?.cancelUpdates()
            }
        })
    }

    // Older iOS runtimes can crash in isolated `deinit`; cleanup only invalidates resources
    deinit {
        updateTask?.cancel()
        timer?.invalidate()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }

    public func start() {
        isActive = true
        setNeedsUpdate()
    }

    public func stop() {
        isActive = false
        cancelUpdates()
    }

    public func setNeedsUpdate() {
        guard isActive, !isSuspended, updateTask == nil else { return }
        // Collection view display callbacks can arrive during layout; read visible views after that pass
        updateTask = Task { @MainActor [weak self] in
            guard !Task.isCancelled, let self else { return }
            updateTask = nil
            updateDates()
        }
    }

    private func updateDates() {
        guard isActive, !isSuspended, let collectionView, collectionView.window != nil,
              UIApplication.shared.applicationState != .background else {
            cancelUpdates()
            return
        }
        let now = getCurrentDate()
        var nextDate: Date?
        var views: [UICollectionReusableView] = collectionView.visibleCells
        views += collectionView.visibleSupplementaryViews(ofKind: UICollectionView.elementKindSectionHeader)
        for case let view as any ActivityDateDisplaying in views {
            if let date = view.updateDate(relativeTo: now), date > now {
                nextDate = min(nextDate ?? date, date)
            }
        }
        guard nextDate != nextUpdateDate else { return }
        timer?.invalidate()
        timer = nil
        nextUpdateDate = nextDate
        guard let nextDate else { return }
        let timer = Timer(timeInterval: nextDate.timeIntervalSince(now), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.timer = nil
                self?.nextUpdateDate = nil
                self?.setNeedsUpdate()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func cancelUpdates() {
        updateTask?.cancel()
        updateTask = nil
        timer?.invalidate()
        timer = nil
        nextUpdateDate = nil
    }
}
