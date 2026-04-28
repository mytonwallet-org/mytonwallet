import Foundation
import OSLog
import QuartzCore
import UIKit

enum NftDetailsPerformance {
    static let signposter = OSSignposter(subsystem: "com.mytonwallet.air", category: "NftDetails")

    #if DEBUG
    private static let logger = Logger(subsystem: "com.mytonwallet.air", category: "NftDetails")

    @inline(__always)
    fileprivate static func logNotice(_ message: () -> String) {
        let text = message()
        logger.notice("[NftDetails]: \(text, privacy: .public)")
    }

    @inline(__always)
    fileprivate static func logInfo(_ message: () -> String) {
        let text = message()
        logger.info("[NftDetails]: \(text, privacy: .public)")
    }

    @inline(__always)
    fileprivate static func logDebug(_ message: () -> String) {
        let text = message()
        logger.debug("[NftDetails]: \(text, privacy: .public)")
    }
    #else
    @inline(__always)
    fileprivate static func logNotice(_ message: () -> String) {}

    @inline(__always)
    fileprivate static func logInfo(_ message: () -> String) {}

    @inline(__always)
    fileprivate static func logDebug(_ message: () -> String) {}
    #endif

    struct MeasureHandle {
        fileprivate let name: StaticString
        fileprivate let state: OSSignpostIntervalState
        fileprivate let t0: CFAbsoluteTime

        fileprivate init(name: StaticString, state: OSSignpostIntervalState, t0: CFAbsoluteTime) {
            self.name = name
            self.state = state
            self.t0 = t0
        }
    }

    /// Wall-clock threshold for SLOW console warnings. 120 Hz frame budget ≈ 8.33 ms; 60 Hz ≈ 16.67 ms.
    private static let slowIntervalThresholdSeconds: CFTimeInterval = 0.008

    @inline(__always)
    static func beginMeasure(_ name: StaticString) -> MeasureHandle {
        MeasureHandle(
            name: name,
            state: signposter.beginInterval(name),
            t0: CFAbsoluteTimeGetCurrent()
        )
    }
    
    @inline(__always)
    static func endMeasure(_ handle: MeasureHandle) {
        signposter.endInterval(handle.name, handle.state)
        let elapsed = CFAbsoluteTimeGetCurrent() - handle.t0
        if elapsed > slowIntervalThresholdSeconds {
            let ms = elapsed * 1000
            logNotice {
                "SLOW '\(handle.name)' duration=\(String(format: "%.2f", ms))"
            }
        }
    }

    @inline(__always)
    static func measureInterval<T>(_ name: StaticString, _ block: () throws -> T) rethrows -> T {
        let handle = beginMeasure(name)
        defer { endMeasure(handle) }
        return try block()
    }

    @MainActor
    static func markPagerScrollEvent() {
    #if DEBUG
        VsyncScrollEventCounter.shared.bumpScroll()
    #endif
    }

    @MainActor
    static func markMtkBackgroundDraw() {
    #if DEBUG
        VsyncScrollEventCounter.shared.bumpDraw()
    #endif
    }
}

@MainActor
private final class VsyncScrollEventCounter: NSObject {
    static let shared = VsyncScrollEventCounter()

    private var scrollEventsThisFrame = 0
    private var mtkDrawsThisFrame = 0
    private var displayLink: CADisplayLink?
    private var idleFrameCount = 0
    private var isFirstTickAfterDisplayLinkAttach = false
    private static var didLogScreenRefreshCaps = false

    func bumpScroll() {
        Self.logScreenRefreshCapsOnce()
        scrollEventsThisFrame += 1
        attachLinkIfNeeded()
    }

    func bumpDraw() {
        Self.logScreenRefreshCapsOnce()
        mtkDrawsThisFrame += 1
        attachLinkIfNeeded()
    }

    private static func logScreenRefreshCapsOnce() {
        guard !didLogScreenRefreshCaps else { return }
        didLogScreenRefreshCaps = true
        let maxFps = UIScreen.main.maximumFramesPerSecond
        let native = UIScreen.main.nativeScale
        NftDetailsPerformance.logInfo {
            "UIScreen.maximumFramesPerSecond=\(maxFps) nativeScale=\(native)"
        }
    }

    private func attachLinkIfNeeded() {
        guard displayLink == nil else { return }
        idleFrameCount = 0
        isFirstTickAfterDisplayLinkAttach = true
        let link = CADisplayLink(target: self, selector: #selector(onTick(_:)))
        link.add(to: .main, forMode: .common)
        if #available(iOS 15.0, *) {
            let maxFps = UIScreen.main.maximumFramesPerSecond
            let m = Float(maxFps)
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: m, preferred: m)
        }
        displayLink = link
    }

    @objc private func onTick(_ link: CADisplayLink) {
        let scrollN = scrollEventsThisFrame
        let drawN = mtkDrawsThisFrame
        scrollEventsThisFrame = 0
        mtkDrawsThisFrame = 0

        let skipMultiEventWarnings = isFirstTickAfterDisplayLinkAttach
        isFirstTickAfterDisplayLinkAttach = false

        if scrollN > 0 || drawN > 0 {
            let hz = 1.0 / link.duration
            if scrollN != drawN {
                NftDetailsPerformance.logDebug { "vsync ~\(Int(hz)) Hz scrollDidScroll=\(scrollN) mtk_draw=\(drawN) idle=\(idleFrameCount)"}
            }
            if scrollN > 1 {
                if !skipMultiEventWarnings {
                    NftDetailsPerformance.logDebug { "scrollDidScroll fired \(scrollN)× in one display frame (>1 ⇒ more scroll callbacks than vsync for that frame)." }
                }
            }
            if drawN > scrollN, scrollN > 0, !skipMultiEventWarnings {
                NftDetailsPerformance.logDebug {
                    "mtk_draw (\(drawN)) > scroll (\(scrollN)) — extra draws from layout/trait changes or setNeedsDisplay batching."
                }
            }
            idleFrameCount = 0
            return
        }
        
        // Stop display link after some idle interval
        idleFrameCount += 1
        if idleFrameCount >= 45 {
            displayLink?.invalidate()
            displayLink = nil
            idleFrameCount = 0
        }
    }
}
