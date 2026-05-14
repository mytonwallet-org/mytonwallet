import Foundation
import OSLog
import QuartzCore
import UIKit

enum NftDetailsPerformance {
    static let signposter = OSSignposter(subsystem: "com.mytonwallet.air", category: "NftDetails")

    #if DEBUG
    private static let logger = Logger(subsystem: "com.mytonwallet.air", category: "NftDetails")

    @inline(__always)
    fileprivate static func log(_ message: () -> String) {
        let text = message()
        logger.debug("[NftDetails]: \(text, privacy: .public)")
    }

    #else
    static func log(_ message: () -> String) {}
    #endif

    struct MeasureHandle {
        fileprivate let name: StaticString
        fileprivate let state: OSSignpostIntervalState
        fileprivate let t0: CFAbsoluteTime
        fileprivate let thresholdInterval: Double // in ms
        fileprivate let tag: String?

        fileprivate init(name: StaticString, state: OSSignpostIntervalState, t0: CFAbsoluteTime, thresholdInterval: Double, tag: String? = nil) {
            self.name = name
            self.state = state
            self.t0 = t0
            self.thresholdInterval = thresholdInterval
            self.tag = tag
        }
    }

    @inline(__always)
    static func beginMeasure(_ name: StaticString, threshold: Double? = nil, tag: String? = nil) -> MeasureHandle {

        // Wall-clock threshold for SLOW console warnings. 120 Hz frame budget ≈ 8.33 ms; 60 Hz ≈ 16.67 ms.
        let slowIntervalThreshold = 8.0

        return MeasureHandle(
            name: name,
            state: signposter.beginInterval(name),
            t0: CFAbsoluteTimeGetCurrent(),
            thresholdInterval: threshold ?? slowIntervalThreshold,
            tag: tag
        )
    }
    
    @inline(__always)
    static func endMeasure(_ handle: MeasureHandle) {
        signposter.endInterval(handle.name, handle.state)
        let elapsed = (CFAbsoluteTimeGetCurrent() - handle.t0) * 1000.0
        if elapsed > handle.thresholdInterval {
            log {
                var name = String(describing: handle.name)
                if let tag = handle.tag {
                    name = "\(name) (\(tag))"
                }
                return "😡 SLOW '\(name)' duration=\(String(format: "%.2f", elapsed))"
            }
        }
    }
}
