import Foundation
import simd
import UIKit

private let gamutStepCount = 30

/// The look and feel of the voice ribbon. Lengths are in points and times in seconds; the defaults are the product
/// owner's settings from the prototype.
struct AgentVoiceRibbonParameters: Equatable {
    // MARK: - Shape
    /// From 1 to 3
    var strandCount = 2
    /// Half the braid's height in silence
    var braidRadiusAtRest: Float = 1.2
    /// What full voice adds to `braidRadiusAtRest`
    var braidRadiusGrowth: Float = 10
    /// Strands bend softly towards this distance from the field's middle and never pass it
    var heightLimit: Float = 21
    /// How much thinner the braid gets towards the far end, from 0 to 1
    var taper: Float = 0.45
    /// Half a strand's width in silence
    var strandWidthAtRest: Float = 0.5
    /// What full voice adds to `strandWidthAtRest`
    var strandWidthGrowth: Float = 1.15
    /// Radians per point
    var braidTwist: Float = 0.055
    var braidIrregularity: Float = 1.2
    /// How much the strands' heights differ
    var strandSpread: Float = 0.12
    /// How far the braid's axis bends
    var bend: Float = 2.2
    var bendLength: Float = 25
    /// Radians per point; at 0 each silk strand turns as a whole
    var silkTwist: Float = 0
    /// How wide the braid opens where it leaves the Stop circle
    var flare: Float = 2.5
    /// Extra turns, in radians, where the braid leaves the Stop circle
    var curl: Float = 1.2
    /// The birth zone at the Stop circle is three times as long
    var flareLength: Float = 6
    /// How long the ribbon takes to fade out towards the ✕ pill
    var fadeLength: Float = 56

    // MARK: - Motion
    /// How long a syllable takes to travel from the Stop circle to the far end
    var syllableDelay: Float = 1
    /// How long a syllable takes to fade on the ribbon; shorter makes separate syllables stand out
    var syllableRelease: Float = 0.15
    /// Radians per second
    var braidSpeedAtRest: Float = 1.7
    /// What full voice adds to `braidSpeedAtRest`
    var braidSpeedGrowth: Float = 9
    /// Radians per second; full voice triples it
    var silkSpeed: Float = 4
    var bendSpeed: Float = 0.5
    /// How much the braid swells and dims in silence
    var breath: Float = 0.25

    // MARK: - Light
    var coreBrightness: Float = 0.65
    /// A share of the braid's radius
    var coreWidth: Float = 0.4
    var glowWidth: Float = 1.8
    var glowStrength: Float = 0.64
    /// The glint on the crest nearest to the viewer
    var glint: Float = 1.7
    /// How bright the farthest strands are
    var farStrandBrightness: Float = 0.18

    // MARK: - Colour
    /// Degrees from the accent's hue to the deep colour; the glow and the highlights turn the other way
    var hueSpread: Float = 40
    var chroma: Float = 1.3
    /// OKLab lightness added to the palette in the dark theme
    var darkLightness: Float = 0
    /// OKLab lightness added to the palette in the light theme
    var lightLightness: Float = 0
    /// How far glints turn white
    var whitening: Float = 0.86

    // MARK: - Sensitivity
    var gain: Float = 1.75
    /// Levels below it are silence
    var gate: Float = 0.02
    /// Below 1 it makes quiet speech show more
    var gamma: Float = 0.55
    /// Follows the room's noise floor instead of keeping `gate`
    var isGateAdaptive = false
    var attack: Float = 0.04
    var release: Float = 0.3
    var slowAttack: Float = 0.25
    var slowRelease: Float = 0.9

    // MARK: - Transitions
    var startDuration: Float = 0.5
    var stopDuration: Float = 0.5
    var cancelDuration: Float = 0.35
    var sendDuration: Float = 0.16
}

/// Matches `AgentVoiceRibbonUniforms` in AgentVoiceRibbon.metal: 512 bytes, the members described there. The
/// `SIMD64<Float>` holds its sixteen `float4` of history in a row.
struct AgentVoiceRibbonUniforms {
    static let byteCount = 512

    var canvas = SIMD4<Float>()
    var layout = SIMD4<Float>()
    var clocks = SIMD4<Float>()
    var levels = SIMD4<Float>()
    var transition = SIMD4<Float>()
    var braid = SIMD4<Float>()
    var radius = SIMD4<Float>()
    var strand = SIMD4<Float>()
    var bend = SIMD4<Float>()
    var flare = SIMD4<Float>()
    var light = SIMD4<Float>()
    var specular = SIMD4<Float>()
    var deep = SIMD4<Float>()
    var core = SIMD4<Float>()
    var glow = SIMD4<Float>()
    var hot = SIMD4<Float>()
    var history = SIMD64<Float>()
}

/// sRGB-encoded colours of the ribbon, derived from the accent
struct AgentVoiceRibbonPalette: Equatable {
    var deep: SIMD3<Float>
    var core: SIMD3<Float>
    var glow: SIMD3<Float>
    var hot: SIMD3<Float>
}

/// Everything the voice ribbon keeps from frame to frame: the levels, the clocks, the history of syllables the shader
/// reads and the start and end transitions. The host calls `step(deltaTime:rawLevel:)` once a frame and
/// draws with `makeUniforms(size:scale:accent:isDark:isRightToLeft:)`.
///
/// The view spans the field's height and starts the strip's spacing after the ✕ pill's trailing edge. Ribbon x, which
/// the uniforms use, starts `viewOrigin` points before it, at the field's leading edge, as in the
/// prototype.
struct AgentVoiceRibbonModel {
    var parameters = AgentVoiceRibbonParameters()
    /// Holds the ribbon still: only its brightness follows the voice
    var isReduceMotion = false
    /// From the view's leading edge to the Stop circle's centre, points
    var stopCenter: Float = 236

    private(set) var isRecording = false
    /// The recording has ended and its transition is over, so nothing is drawn
    var isFinished: Bool {
        !isRecording && presence < Self.finishedPresence
    }

    private var ending = Ending.stop
    /// Springs to 1 while recording and to 0 after it
    private var presence: Float = 0
    private var presenceVelocity: Float = 0
    private var desaturation: Float = 0
    private var gate: Float = AgentVoiceRibbonParameters().gate
    private var averageLevel: Float = 0
    private var floorSamples = [Float](repeating: 0.01, count: AgentVoiceRibbonModel.floorSampleCount)
    private var floorSampleAge: Float = 0
    private var fastLevel: Float = 0
    private var syllableLevel: Float = 0
    private var slowLevel: Float = 0
    private var braidPhase: Float = 0
    private var silkPhase: Float = 0
    private var bendPhase: Float = 0
    private var breathTime: Float = 0
    /// The syllable level at 60 Hz, newest first; `history[0]` is the current level
    private var history = [Float](repeating: 0, count: AgentVoiceRibbonModel.historyCount)
    /// How long ago `history[1]` was recorded
    private var historyAge: Float = 0

    mutating func start() {
        isRecording = true
        ending = .stop
        desaturation = 0
        // A recording that starts while the previous one still fades out keeps its thread
        guard presence < Self.coldStartPresence else { return }
        for index in history.indices {
            history[index] = 0
        }
        fastLevel = 0
        syllableLevel = 0
        slowLevel = 0
    }

    /// Gathers the thread back into the Stop circle
    mutating func stop() {
        end(.stop)
    }

    /// Fades the thread out in grey
    mutating func cancel() {
        end(.cancel)
    }

    /// Slides the thread into the Send pill
    mutating func send() {
        end(.send)
    }

    /// `rawLevel` is the latest peak of the microphone's signal, from 0 to 1
    mutating func step(deltaTime: Float, rawLevel: Float) {
        let deltaTime = min(max(deltaTime, 0), Self.maxDeltaTime)
        let level = isRecording ? limit(rawLevel * parameters.gain, 0, 1) : 0
        updateGate(level: level, deltaTime: deltaTime)
        updateLevels(level: level, deltaTime: deltaTime)
        advanceClocks(deltaTime: deltaTime)
        updatePresence(deltaTime: deltaTime)
        recordHistory(deltaTime: deltaTime)
    }

    /// `size` is the view's size and `scale` its drawable pixels per point. Pass `accent` resolved for the current
    /// traits.
    func makeUniforms(
        size: CGSize,
        scale: Float,
        accent: UIColor,
        isDark: Bool,
        isRightToLeft: Bool
    ) -> AgentVoiceRibbonUniforms {
        assert(MemoryLayout<AgentVoiceRibbonUniforms>.stride == AgentVoiceRibbonUniforms.byteCount)
        let transition = makeTransition()
        let palette = makeAgentVoiceRibbonPalette(accent: getComponents(of: accent), isDark: isDark, parameters: parameters)
        let height = Float(size.height)
        var uniforms = AgentVoiceRibbonUniforms()
        uniforms.canvas = SIMD4(Float(size.width), height, scale, isRightToLeft ? 1 : 0)
        uniforms.layout = SIMD4(
            Self.farEnd,
            Self.farEnd + parameters.fadeLength,
            Self.viewOrigin + stopCenter,
            Self.viewOrigin
        )
        uniforms.clocks = SIMD4(braidPhase, silkPhase, bendPhase, breathTime)
        uniforms.levels = SIMD4(fastLevel, slowLevel, isReduceMotion ? 1 : 0, historyAge)
        uniforms.transition = SIMD4(transition.reveal, transition.opacity, transition.slide, desaturation)
        uniforms.braid = SIMD4(
            Float(limit(parameters.strandCount, 1, 3)),
            parameters.braidTwist,
            parameters.braidIrregularity,
            parameters.strandSpread
        )
        uniforms.radius = SIMD4(
            parameters.braidRadiusAtRest,
            parameters.braidRadiusGrowth,
            parameters.heightLimit,
            parameters.taper
        )
        uniforms.strand = SIMD4(
            parameters.strandWidthAtRest,
            parameters.strandWidthGrowth,
            parameters.silkTwist,
            parameters.farStrandBrightness
        )
        uniforms.bend = SIMD4(parameters.bend, parameters.bendLength, parameters.breath, parameters.syllableDelay)
        uniforms.flare = SIMD4(parameters.flare, parameters.curl, parameters.flareLength, 0)
        uniforms.light = SIMD4(
            parameters.coreBrightness,
            parameters.coreWidth,
            parameters.glowWidth,
            parameters.glowStrength
        )
        uniforms.specular = SIMD4(parameters.glint, parameters.whitening, isDark ? 1 : 0, 0)
        uniforms.deep = SIMD4(palette.deep.x, palette.deep.y, palette.deep.z, 0)
        uniforms.core = SIMD4(palette.core.x, palette.core.y, palette.core.z, 0)
        uniforms.glow = SIMD4(palette.glow.x, palette.glow.y, palette.glow.z, 0)
        uniforms.hot = SIMD4(palette.hot.x, palette.hot.y, palette.hot.z, 0)
        for (index, value) in history.enumerated() {
            uniforms.history[index] = value
        }
        return uniforms
    }

    private mutating func end(_ ending: Ending) {
        isRecording = false
        self.ending = ending
    }

    /// The adaptive gate sits just above the quietest 80 ms average of the last 1.5 s
    private mutating func updateGate(level: Float, deltaTime: Float) {
        averageLevel += (level - averageLevel) * (1 - exp(-deltaTime / Self.floorAveragingTime))
        floorSampleAge += deltaTime
        while floorSampleAge >= Self.sampleInterval {
            floorSampleAge -= Self.sampleInterval
            shiftOlder(&floorSamples)
            floorSamples[0] = averageLevel
        }
        let target: Float
        if parameters.isGateAdaptive {
            let quietest = floorSamples.min() ?? 0
            target = min(max(1.6 * quietest + 0.005, max(0.006, parameters.gate * 0.6)), 0.035)
        } else {
            target = parameters.gate
        }
        let gateTime: Float = target > gate ? 2 : 0.2
        gate += (target - gate) * (1 - exp(-deltaTime / gateTime))
    }

    private mutating func updateLevels(level: Float, deltaTime: Float) {
        let target = pow(max(0, level - gate) / (1 - gate), parameters.gamma)
        let fastTime: Float = isReduceMotion
            ? (target > fastLevel ? 0.15 : 0.45)
            : (target > fastLevel ? parameters.attack : parameters.release)
        fastLevel += (target - fastLevel) * (1 - exp(-deltaTime / fastTime))
        // A sharper level than `fastLevel`, so separate syllables travel along the ribbon
        let syllableTime: Float = isReduceMotion
            ? 0.3
            : (target > syllableLevel ? Self.syllableAttack : parameters.syllableRelease)
        syllableLevel += (target - syllableLevel) * (1 - exp(-deltaTime / syllableTime))
        let slowTime = fastLevel > slowLevel ? parameters.slowAttack : parameters.slowRelease
        slowLevel += (fastLevel - slowLevel) * (1 - exp(-deltaTime / slowTime))
    }

    /// Phases are integrated rather than computed from time, so a change of speed never makes them jump
    private mutating func advanceClocks(deltaTime: Float) {
        guard !isReduceMotion else { return }
        let fullTurn = 2 * Float.pi
        braidPhase += deltaTime * (parameters.braidSpeedAtRest + parameters.braidSpeedGrowth * fastLevel)
        braidPhase = braidPhase.truncatingRemainder(dividingBy: fullTurn)
        silkPhase += deltaTime * parameters.silkSpeed * (1 + 2 * fastLevel)
        silkPhase = silkPhase.truncatingRemainder(dividingBy: fullTurn)
        bendPhase += deltaTime * parameters.bendSpeed * (1 + 3 * slowLevel)
        breathTime += deltaTime
    }

    /// A critically damped spring that settles within the transition's duration
    private mutating func updatePresence(deltaTime: Float) {
        let duration: Float
        if isRecording {
            duration = parameters.startDuration
        } else {
            switch ending {
            case .stop: duration = parameters.stopDuration
            case .cancel: duration = parameters.cancelDuration
            case .send: duration = parameters.sendDuration
            }
        }
        let frequency = 4.6 / duration
        let offset = presence - (isRecording ? 1 : 0)
        presenceVelocity += (-frequency * frequency * offset - 2 * frequency * presenceVelocity) * deltaTime
        presence = limit(presence + presenceVelocity * deltaTime, 0, 1)
        let desaturationTarget: Float = !isRecording && ending == .cancel ? 1 : 0
        let desaturationTime = max(0.03, parameters.cancelDuration * 0.3)
        desaturation += (desaturationTarget - desaturation) * (1 - exp(-deltaTime / desaturationTime))
    }

    private mutating func recordHistory(deltaTime: Float) {
        historyAge += deltaTime
        while historyAge >= Self.sampleInterval {
            historyAge -= Self.sampleInterval
            shiftOlder(&history)
        }
        history[0] = syllableLevel
    }

    private func makeTransition() -> Transition {
        if isReduceMotion {
            return Transition(reveal: 1, opacity: presence, slide: 0)
        }
        if isRecording || ending == .stop {
            return Transition(reveal: presence, opacity: min(1, presence * 2.5), slide: 0)
        }
        if ending == .cancel {
            return Transition(reveal: 1, opacity: presence, slide: 0)
        }
        return Transition(reveal: 1, opacity: pow(presence, 0.7), slide: 1 - presence)
    }

    private func getComponents(of color: UIColor) -> SIMD3<Float> {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        _ = color.getRed(&red, green: &green, blue: &blue, alpha: nil)
        return SIMD3(Float(limit(red, 0, 1)), Float(limit(green, 0, 1)), Float(limit(blue, 0, 1)))
    }

    private enum Ending {
        case stop
        case cancel
        case send
    }

    private struct Transition {
        /// How far the thread is drawn out of the Stop circle
        var reveal: Float
        var opacity: Float
        /// How far the thread has slid into the Send pill
        var slide: Float
    }

    /// The ✕ pill's trailing edge in the field: an 8-point inset and the 40-point pill
    private static let crossEnd: Float = 48
    /// The view's leading edge: the strip starts 10 points after the ✕ pill
    private static let viewOrigin: Float = crossEnd + 10
    /// Ribbon x of the far end, 12 points after the ✕ pill
    private static let farEnd: Float = crossEnd + 12
    private static let historyCount = 64
    private static let floorSampleCount = 90
    private static let sampleInterval: Float = 1 / 60
    private static let floorAveragingTime: Float = 0.08
    private static let syllableAttack: Float = 0.025
    /// Longer frames, such as after a stall, advance the ribbon by this much only
    private static let maxDeltaTime: Float = 0.05
    private static let finishedPresence: Float = 0.002
    /// Below it a new recording starts from silence
    private static let coldStartPresence: Float = 0.05
}

/// The accent's palette for the ribbon in OKLCH: a deep colour, the core, a lighter glow and almost white highlights,
/// with hues spread around the accent's. `accent` is sRGB-encoded, from 0 to 1. A grey accent gets a silver palette.
func makeAgentVoiceRibbonPalette(
    accent: SIMD3<Float>,
    isDark: Bool,
    parameters: AgentVoiceRibbonParameters
) -> AgentVoiceRibbonPalette {
    let accentOklch = convertToOklch(accent)
    let lightness = accentOklch.lightness
    let chroma = accentOklch.chroma
    let hue = accentOklch.hue
    let isGrey = chroma < 0.025
    let chromaScale = Double(parameters.chroma)
    let spread = Double(parameters.hueSpread)

    func scaleChroma(_ factor: Double) -> Double {
        isGrey ? chroma : min(chroma * factor * chromaScale, chroma + 0.04 * chromaScale)
    }

    if isDark {
        let shift = Double(parameters.darkLightness)
        return AgentVoiceRibbonPalette(
            deep: makeColor(lightness: limit(lightness - 0.06 + shift, 0.42, 0.62), chroma: scaleChroma(1), hue: hue - spread),
            core: makeColor(lightness: limit(lightness + 0.075 + shift, 0.60, 0.76), chroma: scaleChroma(1), hue: hue),
            glow: makeColor(
                lightness: limit(lightness + 0.225 + shift, 0.75, 0.90),
                chroma: scaleChroma(0.87),
                hue: hue + 0.6 * spread
            ),
            hot: makeColor(lightness: 0.96, chroma: min(chroma * 0.30, 0.05), hue: hue + 1.2 * spread)
        )
    }
    let shift = Double(parameters.lightLightness)
    return AgentVoiceRibbonPalette(
        deep: makeColor(lightness: limit(lightness - 0.07 + shift, 0.38, 0.56), chroma: scaleChroma(1.05), hue: hue - spread),
        core: makeColor(lightness: limit(lightness + 0.02 + shift, 0.50, 0.66), chroma: scaleChroma(1.05), hue: hue),
        glow: makeColor(
            lightness: limit(lightness + 0.17 + shift, 0.68, 0.84),
            chroma: scaleChroma(0.9),
            hue: hue + 0.6 * spread
        ),
        hot: makeColor(lightness: 0.985, chroma: min(chroma * 0.20, 0.03), hue: hue + 1.2 * spread)
    )
}

private struct Oklch {
    var lightness: Double
    var chroma: Double
    /// Degrees
    var hue: Double
}

private func convertToOklch(_ color: SIMD3<Float>) -> Oklch {
    let red = convertToLinear(Double(color.x))
    let green = convertToLinear(Double(color.y))
    let blue = convertToLinear(Double(color.z))
    let long = cbrt(0.4122214708 * red + 0.5363325363 * green + 0.0514459929 * blue)
    let medium = cbrt(0.2119034982 * red + 0.6806995451 * green + 0.1073969566 * blue)
    let short = cbrt(0.0883024619 * red + 0.2817188376 * green + 0.6299787005 * blue)
    let lightness = 0.2104542553 * long + 0.7936177850 * medium - 0.0040720468 * short
    let greenRed = 1.9779984951 * long - 2.4285922050 * medium + 0.4505937099 * short
    let blueYellow = 0.0259040371 * long + 0.7827717662 * medium - 0.8086757660 * short
    let chroma = (greenRed * greenRed + blueYellow * blueYellow).squareRoot()
    return Oklch(lightness: lightness, chroma: chroma, hue: atan2(blueYellow, greenRed) * 180 / Double.pi)
}

/// An sRGB-encoded colour of the given OKLCH. Out of gamut the chroma shrinks and the lightness and hue stay.
private func makeColor(lightness: Double, chroma: Double, hue: Double) -> SIMD3<Float> {
    var currentChroma = chroma
    for _ in 0..<gamutStepCount {
        let linear = convertToLinearSrgb(lightness: lightness, chroma: currentChroma, hue: hue)
        if linear.min() >= -0.001 && linear.max() <= 1.001 {
            return encodeSrgb(linear)
        }
        currentChroma *= 0.92
    }
    return encodeSrgb(convertToLinearSrgb(lightness: lightness, chroma: 0, hue: hue))
}

private func convertToLinearSrgb(lightness: Double, chroma: Double, hue: Double) -> SIMD3<Double> {
    let angle = hue * Double.pi / 180
    let greenRed = chroma * cos(angle)
    let blueYellow = chroma * sin(angle)
    let longRoot = lightness + 0.3963377774 * greenRed + 0.2158037573 * blueYellow
    let mediumRoot = lightness - 0.1055613458 * greenRed - 0.0638541728 * blueYellow
    let shortRoot = lightness - 0.0894841775 * greenRed - 1.2914855480 * blueYellow
    let long = longRoot * longRoot * longRoot
    let medium = mediumRoot * mediumRoot * mediumRoot
    let short = shortRoot * shortRoot * shortRoot
    return SIMD3(
        4.0767416621 * long - 3.3077115913 * medium + 0.2309699292 * short,
        -1.2684380046 * long + 2.6097574011 * medium - 0.3413193965 * short,
        -0.0041960863 * long - 0.7034186147 * medium + 1.7076147010 * short
    )
}

private func encodeSrgb(_ linear: SIMD3<Double>) -> SIMD3<Float> {
    SIMD3(
        Float(convertToGamma(limit(linear.x, 0, 1))),
        Float(convertToGamma(limit(linear.y, 0, 1))),
        Float(convertToGamma(limit(linear.z, 0, 1)))
    )
}

private func convertToLinear(_ value: Double) -> Double {
    value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
}

private func convertToGamma(_ value: Double) -> Double {
    value <= 0.0031308 ? 12.92 * value : 1.055 * pow(value, 1 / 2.4) - 0.055
}

private func shiftOlder(_ samples: inout [Float]) {
    for index in stride(from: samples.count - 1, to: 0, by: -1) {
        samples[index] = samples[index - 1]
    }
}

private func limit<Value: Comparable>(_ value: Value, _ lower: Value, _ upper: Value) -> Value {
    min(max(value, lower), upper)
}
