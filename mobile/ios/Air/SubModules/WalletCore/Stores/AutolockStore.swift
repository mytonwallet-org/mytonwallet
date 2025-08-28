
import Foundation
import WalletContext
import UIKit
import Kingfisher

public let DEFAULT_AUTOLOCK_OPTION = MAutolockOption.tenMinutes

private let log = Log("AutolockStore")
private let isAppLockEnabledKey = "settings.isAppLockEnabled"
private let autolockValueKey = "settings.autolockValue"

public final class AutolockStore: NSObject {

    public static let shared = AutolockStore()
    
    private var timer: Timer?
    
    private override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(restartTimer), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(invalidateTimer), name: UIApplication.didBecomeActiveNotification, object: nil)
    }
    
    public var autolockOption: MAutolockOption {
        get {
            if let s = GlobalStorage[autolockValueKey] as? String, let option = MAutolockOption(rawValue: s) {
                return option
            }
            return DEFAULT_AUTOLOCK_OPTION
        }
        set {
            GlobalStorage.update {
                if newValue != .never {
                    $0[isAppLockEnabledKey] = true
                }
                $0[autolockValueKey] = newValue.rawValue
            }
            Task {
                try? await GlobalStorage.syncronize()
            }
            restartTimerIfValid()
        }
    }
    
    private func restartTimerIfValid() {
        if self.timer?.isValid == true {
            restartTimer()
        }
    }
    
    @objc private func restartTimer() {
        self.timer?.invalidate()
        if let period = autolockOption.period {
            self.timer = Timer.scheduledTimer(withTimeInterval: period, repeats: false) { _ in
                Task { @MainActor in AppActions.lockApp(animated: false) }
            }
        }
    }
    
    @objc private func invalidateTimer() {
        self.timer?.invalidate()
    }
}

