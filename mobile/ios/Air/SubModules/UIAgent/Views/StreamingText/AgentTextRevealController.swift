import Foundation

final class AgentTextRevealController {
    private static let velocityTau: Double = 0.08
    private static let gapEwmaAlpha: Double = 0.4
    private static let initialGap: Double = 0.5
    private static let stallFloor: Double = 0.10
    private static let finalizeTime: Double = 0.2
    private static let frameDtCap: Double = 0.05
    private static let initialInputRate: Double = 80.0
    private static let maxInputRate: Double = 240.0
    private static let inputRateHoldChunks: Double = 4.0
    private static let inputRateRampChunks: Double = 16.0
    private static let maximumRevealLag = 32

    private var velocity: Double = 0.0
    private var avgInterArrival: Double = AgentTextRevealController.initialGap
    private var lastSampleTime: Double?
    private var lastSampleLength: Int?
    private var predictedNextArrivalTime: Double?
    private var chunkCount: Int = 0
    private var lastFrameTime: Double?
    private let durationMultiplier: Double

    private(set) var isFinalizing: Bool = false
    private(set) var revealedCount: Double
    private(set) var latestLength: Int

    init(initialRevealedCount: Int, initialLength: Int, durationMultiplier: Double = 1.0) {
        self.revealedCount = Double(initialRevealedCount)
        self.latestLength = initialLength
        self.durationMultiplier = max(0.0001, durationMultiplier)
    }

    var currentGlyphCount: Int {
        Int(revealedCount)
    }

    private var acceleratedInputRate: Double {
        let afterHold = max(0.0, Double(max(0, chunkCount - 1)) - Self.inputRateHoldChunks)
        let ramp = min(1.0, afterHold / Self.inputRateRampChunks)
        return Self.initialInputRate + (Self.maxInputRate - Self.initialInputRate) * ramp
    }

    func observeUpdate(latestLength: Int, at now: Double) {
        if let lastLen = lastSampleLength {
            if latestLength > lastLen {
                if let lastTime = lastSampleTime {
                    let interArrival = max(now - lastTime, 0.001)
                    avgInterArrival = Self.gapEwmaAlpha * interArrival + (1.0 - Self.gapEwmaAlpha) * avgInterArrival
                }
                lastSampleTime = now
                lastSampleLength = latestLength
                predictedNextArrivalTime = now + avgInterArrival
                chunkCount += 1
            } else if latestLength < lastLen {
                lastSampleLength = latestLength
            }
        } else {
            lastSampleTime = now
            lastSampleLength = latestLength
            predictedNextArrivalTime = now + avgInterArrival
            chunkCount += 1
        }
        self.latestLength = latestLength
        let minimumRevealedCount = max(0, latestLength - Self.maximumRevealLag)
        if revealedCount < Double(minimumRevealedCount) {
            revealedCount = Double(minimumRevealedCount)
        }
        if revealedCount > Double(latestLength) {
            revealedCount = Double(latestLength)
        }
    }

    func finalize(finalLength: Int) {
        latestLength = finalLength
        isFinalizing = true
        if revealedCount > Double(finalLength) {
            revealedCount = Double(finalLength)
        }
    }

    func tick(now: Double) -> (revealedGlyphCount: Int, isComplete: Bool) {
        let dt = min(now - (lastFrameTime ?? now), Self.frameDtCap)
        let lag = max(0.0, Double(latestLength) - revealedCount)
        let inputRate = acceleratedInputRate
        let targetVelocity: Double
        if isFinalizing {
            targetVelocity = max(velocity, lag / Self.finalizeTime)
        } else if chunkCount < 2 {
            targetVelocity = lag > 0.0 ? inputRate : 0.0
        } else if let predNext = predictedNextArrivalTime {
            let timeToNext = max(Self.stallFloor, predNext - now)
            let catchUpFloor = chunkCount <= Int(Self.inputRateHoldChunks) + 1
                ? inputRate * 0.15
                : inputRate * 0.3
            targetVelocity = max(catchUpFloor, lag / timeToNext)
        } else {
            targetVelocity = lag > 0.0 ? inputRate : 0.0
        }
        let smoothing = min(1.0, dt / Self.velocityTau)
        velocity += (targetVelocity - velocity) * smoothing
        revealedCount = min(Double(latestLength), revealedCount + velocity * dt / durationMultiplier)
        lastFrameTime = now
        let isComplete = isFinalizing && revealedCount >= Double(latestLength)
        return (Int(revealedCount), isComplete)
    }
}
