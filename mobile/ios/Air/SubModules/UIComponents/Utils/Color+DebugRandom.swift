import SwiftUI

#if DEBUG
extension Color {
    /// Generates a random, vibrant color for debugging purposes.
    /// Ensures newly generated color is distinct from recently generated, preventing similar color follow one by one.
    /// Prevents hue repetition by checking for circular hue differences.
    /// Ensures the color is not too dark or light for better visibility during development.
    @MainActor
    public static func debugRandom(darkColors: Bool = false,
                                   hueRange: ClosedRange<Double> = 0 ... 1.0,
                                   saturationRange: ClosedRange<Double> = 0.6 ... 1.0) -> Color {
        let hue = controlledRandomHue(inRange: hueRange)

        // Set saturation to a high value to ensure vibrant colors
        let saturation = Double.random(in: saturationRange)

        // Set brightness to avoid colors that are too dark or too light.
        let brightnessRange = darkColors ? 0.23 ... 0.5 : 0.65 ... 0.97
        let brightness = controlledRandomBrightness(in: brightnessRange)

        return Color(hue: hue, saturation: saturation, brightness: brightness)
    }

    @MainActor
    private static var recentlyGeneratedHues = [Double]()

    @MainActor
    private static var brightnessHistory: [Int] = []

    /// Generates visually distinct, pseudo-random hues for debugging or testing.
    /// Avoids repeating recently generated hues and ensures consecutive hues are well-separated.
    /// The hue circle is divided into discrete steps to simplify distance checks and prevent clustering.
    @MainActor
    private static func controlledRandomHue(inRange range: ClosedRange<Double>) -> Double {
        let lowerBound = range.lowerBound < 0 ? 0 : range.lowerBound
        let upperBound = range.upperBound > 1 ? 1 : range.upperBound
        guard (upperBound - lowerBound) > 0.01 else { return Double.random(in: range) }

        let stepsCount = 12 // Divide hue circle into discrete steps
        let historySize = 9 // How many recent hues to avoid
        let hueStep: Double = (upperBound - lowerBound) / Double(stepsCount)

        // Available buckets excluding recently used ones
        let discreteStepsRange: Range<Int> = 0 ..< stepsCount

        let availableDiscreteSteps: [Int] = discreteStepsRange.filter { step in
            let candidateHue = Double(step) * hueStep

            let distinctFromAllRecent: Bool = recentlyGeneratedHues.allSatisfy { recentHue in
                circularDifference(recentHue, candidateHue) >= (hueStep / 2)
            }
            let distinctFromLatest: Bool = recentlyGeneratedHues.prefix(5).allSatisfy { recentHue in
                circularDifference(recentHue, candidateHue) >= hueStep
            }
            return distinctFromAllRecent && distinctFromLatest
        }

        // Pick a discrete step
        let discreteStep: Int = availableDiscreteSteps.randomElement() ?? Int.random(in: discreteStepsRange)
        let baseHue: Double = lowerBound + Double(discreteStep) * hueStep
        // Store hue history
        if recentlyGeneratedHues.count >= historySize {
            recentlyGeneratedHues.removeLast()
        }
        recentlyGeneratedHues.insert(baseHue, at: 0)

        // Add jitter
        let randomSubStep: Double = .random(in: 0 ..< hueStep)
        let finalHue: Double = (baseHue + randomSubStep)

        return finalHue
    }

    /// Computes circular difference between two hues (0...1) around the hue circle.
    private static func circularDifference(_ hue1: Double, _ hue2: Double) -> Double {
        let diff: Double = abs(hue1 - hue2)
        return min(diff, 1.0 - diff)
    }

    /// Generates a pseudo-random brightness, ensuring consecutive values visually differ significantly.
    /// The range is divided into discrete steps, and upper-biased jitter is added for variation.
    /// Recent steps are remembered to avoid repetition and create visually distinct brightnesses.
    @MainActor
    private static func controlledRandomBrightness(in range: ClosedRange<Double>) -> Double {
        let lowerBound = range.lowerBound < 0 ? 0 : range.lowerBound
        let upperBound = range.upperBound > 1 ? 1 : range.upperBound
        guard (upperBound - lowerBound) > 0.01 else { return Double.random(in: range) }

        let stepsCount = 5
        let historySize = 3
        let brightnessStep: Double = (range.upperBound - range.lowerBound) / Double(stepsCount)

        // Available buckets excluding recently used ones
        let discreteStepsRange = 0 ..< stepsCount
        let availableDiscreteSteps = discreteStepsRange.filter {
            !brightnessHistory.contains($0)
        }

        let discreteStep: Int = availableDiscreteSteps.randomElement() ?? Int.random(in: discreteStepsRange)

        if brightnessHistory.count >= historySize {
            brightnessHistory.removeLast()
        }

        let randomSubStep: Double = biasedJitter(maxValue: brightnessStep)
        brightnessHistory.insert(discreteStep, at: 0)

        // Generate brightness inside bucket with jitter
        let base = lowerBound + Double(discreteStep) * brightnessStep
        return base + randomSubStep
    }

    /// generates a random offset (jitter) that is more likely to be near the upper end of the specified range.
    private static func biasedJitter(maxValue: Double) -> Double {
        let upperBiasStrength: Double = 2 // how strongly values tend to upper bound
        let distanceFromUpperBound = Double.random(in: 0 ... 1)
        let compressedDistance = pow(distanceFromUpperBound, upperBiasStrength)
        let upperBiasedSample = 1 - compressedDistance // flip the value toward the upper bound
        let jitter = upperBiasedSample * maxValue
        return jitter
    }
}
#endif
