import UIKit
#if canImport(Capacitor)
import Capacitor
#endif

final class MyTonWalletApp: UIApplication {
    private var lastTouchEventTimestamp = TimeInterval(0)

    override func sendEvent(_ event: UIEvent) {
        super.sendEvent(event)

        guard let touches = event.allTouches,
              !touches.isEmpty else {
            return
        }

        let now = Date().timeIntervalSince1970
        guard now >= lastTouchEventTimestamp + 5 else {
            return
        }
        #if canImport(Capacitor)
        guard let vc = UIApplication.shared.sceneKeyWindow?.rootViewController as? CAPBridgeViewController else {
            return
        }
        lastTouchEventTimestamp = now
        vc.bridge?.triggerWindowJSEvent(eventName: "touch")
        #endif
    }
}
