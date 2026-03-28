
import Foundation
import WalletContext
import UIKit
import Kingfisher

public let DEFAULT_AUTOLOCK_OPTION = MAutolockOption.tenMinutes

private let log = Log("AutolockStore")

@MainActor
public final class AutolockStore: NSObject, Sendable {

    public static let shared = AutolockStore()
    
    private var timer: Timer?
    
    private override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(restartTimer), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(invalidateTimer), name: UIApplication.didBecomeActiveNotification, object: nil)
    }
    
    public var autolockOption: MAutolockOption {
        get {
            AppStorageHelper.autolockOption
        }
        set {
            AppStorageHelper.autolockOption = newValue
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
