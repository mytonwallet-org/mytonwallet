package org.mytonwallet.app_air.uiagent.viewControllers.agent.views

import android.graphics.Color
import kotlin.math.PI
import kotlin.math.atan2
import kotlin.math.cbrt
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * The look and feel of the voice ribbon, as on iOS. Lengths are in dp and times in seconds; the defaults are the
 * product owner's settings from the prototype.
 */
internal data class AgentVoiceRibbonParameters(
    /** From 1 to 3 */
    val strandCount: Int = 2,
    /** Half the braid's height in silence */
    val braidRadiusAtRest: Float = 1.2f,
    /** What full voice adds to [braidRadiusAtRest] */
    val braidRadiusGrowth: Float = 10f,
    /** Strands bend softly towards this distance from the field's middle and never pass it */
    val heightLimit: Float = 21f,
    /** How much thinner the braid gets towards the far end, from 0 to 1 */
    val taper: Float = 0.45f,
    /** Half a strand's width in silence */
    val strandWidthAtRest: Float = 0.5f,
    /** What full voice adds to [strandWidthAtRest] */
    val strandWidthGrowth: Float = 1.15f,
    /** Radians per dp */
    val braidTwist: Float = 0.055f,
    val braidIrregularity: Float = 1.2f,
    /** How much the strands' heights differ */
    val strandSpread: Float = 0.12f,
    /** How far the braid's axis bends */
    val bend: Float = 2.2f,
    val bendLength: Float = 25f,
    /** Radians per dp; at 0 each silk strand turns as a whole */
    val silkTwist: Float = 0f,
    /** How wide the braid opens where it leaves the Stop circle */
    val flare: Float = 2.5f,
    /** Extra turns, in radians, where the braid leaves the Stop circle */
    val curl: Float = 1.2f,
    /** The birth zone at the Stop circle is three times as long */
    val flareLength: Float = 6f,
    /** How long the ribbon takes to fade out towards the ✕ pill and towards the Stop circle */
    val fadeLength: Float = 56f,
    /** How long a syllable takes to travel from the Stop circle to the far end */
    val syllableDelay: Float = 1f,
    /** How long a syllable takes to fade on the ribbon; shorter makes separate syllables stand out */
    val syllableRelease: Float = 0.15f,
    /** Radians per second */
    val braidSpeedAtRest: Float = 1.7f,
    /** What full voice adds to [braidSpeedAtRest] */
    val braidSpeedGrowth: Float = 9f,
    /** Radians per second; full voice triples it */
    val silkSpeed: Float = 4f,
    val bendSpeed: Float = 0.5f,
    /** How much the braid swells and dims in silence */
    val breath: Float = 0.25f,
    val coreBrightness: Float = 0.65f,
    /** A share of the braid's radius */
    val coreWidth: Float = 0.4f,
    val glowWidth: Float = 1.8f,
    val glowStrength: Float = 0.64f,
    /** The glint on the crest nearest to the viewer */
    val glint: Float = 1.7f,
    /** How bright the farthest strands are */
    val farStrandBrightness: Float = 0.18f,
    /** Degrees from the accent's hue to the deep colour; the glow and the highlights turn the other way */
    val hueSpread: Float = 40f,
    val chroma: Float = 1.3f,
    /** OKLab lightness added to the palette in the dark theme */
    val darkLightness: Float = 0f,
    /** OKLab lightness added to the palette in the light theme */
    val lightLightness: Float = 0f,
    /** How far glints turn white */
    val whitening: Float = 0.86f,
    val gain: Float = 1.75f,
    /** Levels below it are silence */
    val gate: Float = 0.02f,
    /** Below 1 it makes quiet speech show more */
    val gamma: Float = 0.55f,
    val attack: Float = 0.04f,
    val release: Float = 0.3f,
    val slowAttack: Float = 0.25f,
    val slowRelease: Float = 0.9f,
    val startDuration: Float = 0.5f,
    val stopDuration: Float = 0.5f,
    val cancelDuration: Float = 0.35f,
    val sendDuration: Float = 0.16f
)

/** sRGB colours of the ribbon, derived from the accent, as packed `Color` ints */
internal data class AgentVoiceRibbonPalette(
    val deep: Int,
    val core: Int,
    val glow: Int,
    val hot: Int
)

/**
 * Everything the voice ribbon keeps from frame to frame, as `AgentVoiceRibbonModel` on iOS: the levels, the clocks, the
 * history of syllables and the start and end transitions. The host calls [step] once a frame and draws the
 * braid's cross-sections from [fillSections].
 *
 * The view spans the field's height and starts the field's text gap after the ✕ button. Ribbon x, which the sections
 * use, starts [VIEW_ORIGIN] dp before it, at the field's leading edge, as in the prototype.
 */
internal class AgentVoiceRibbonModel {
    var parameters = AgentVoiceRibbonParameters()

    /** Holds the ribbon still: only its brightness follows the voice */
    var isReduceMotion = false

    /** From the view's leading edge to the Stop circle's centre, in dp */
    var stopCenter = 236f

    var isRecording = false
        private set

    /** The recording has ended and its transition is over, so nothing is drawn */
    val isFinished: Boolean
        get() = !isRecording && presence < FINISHED_PRESENCE

    var fastLevel = 0f
        private set
    var slowLevel = 0f
        private set
    var braidPhase = 0f
        private set
    var silkPhase = 0f
        private set
    var bendPhase = 0f
        private set
    var breathTime = 0f
        private set
    var desaturation = 0f
        private set

    private var ending = Ending.STOP
    private var presence = 0f
    private var presenceVelocity = 0f
    private var syllableLevel = 0f

    /** The syllable level at 60 Hz, newest first; `history[0]` is the current level */
    private val history = FloatArray(HISTORY_COUNT)

    /** How long ago `history[1]` was recorded */
    private var historyAge = 0f

    val transition: Transition
        get() = when {
            isReduceMotion -> Transition(reveal = 1f, opacity = presence, slide = 0f)

            isRecording || ending == Ending.STOP ->
                Transition(reveal = presence, opacity = min(1f, presence * 2.5f), slide = 0f)

            ending == Ending.CANCEL -> Transition(reveal = 1f, opacity = presence, slide = 0f)

            else -> Transition(reveal = 1f, opacity = presence.pow(0.7f), slide = 1 - presence)
        }

    /** Ribbon x of the far end and of the Stop circle's centre, in dp */
    val farEnd: Float get() = FAR_END
    val stopCenterX: Float get() = VIEW_ORIGIN + stopCenter

    fun start() {
        isRecording = true
        ending = Ending.STOP
        desaturation = 0f
        // A recording that starts while the previous one still fades out keeps its thread
        if (presence >= COLD_START_PRESENCE) return
        history.fill(0f)
        fastLevel = 0f
        syllableLevel = 0f
        slowLevel = 0f
    }

    /** Gathers the thread back into the Stop circle */
    fun stop() = end(Ending.STOP)

    /** Fades the thread out in grey */
    fun cancel() = end(Ending.CANCEL)

    /** Slides the thread into the Send pill */
    fun send() = end(Ending.SEND)

    /** [rawLevel] is the latest peak of the microphone's signal, from 0 to 1 */
    fun step(deltaTime: Float, rawLevel: Float) {
        val delta = deltaTime.coerceIn(0f, MAX_DELTA_TIME)
        val level = if (isRecording) (rawLevel * parameters.gain).coerceIn(0f, 1f) else 0f
        updateLevels(level, delta)
        advanceClocks(delta)
        updatePresence(delta)
        recordHistory(delta)
    }

    /**
     * Writes the braid's cross-section at ribbon x `start + index * spacing` for [count] samples: its axis from the
     * view's middle, its radius, the syllable level that reached it and its opacity, four values each
     */
    fun fillSections(out: FloatArray, start: Float, spacing: Float, count: Int) {
        val transition = transition
        for (index in 0 until count) {
            val section = makeSection(start + index * spacing, transition)
            out[index * 4] = section.center
            out[index * 4 + 1] = section.radius
            out[index * 4 + 2] = section.level
            out[index * 4 + 3] = section.opacity
        }
    }

    /** The shader's strand: y from the view's middle and depth, 1 nearest to the viewer, for a section */
    fun getStrand(center: Float, radius: Float, x: Float, index: Int, out: FloatArray) {
        val count = parameters.strandCount.coerceIn(1, 3).toFloat()
        val strandIndex = index.toFloat()
        val offset = strandIndex - (count - 1) / 2
        val wobble = 0.10f * sin(x / 37 + strandIndex * 2 + bendPhase * 1.3f)
        val strandRadius = radius * (1 + parameters.strandSpread * offset + wobble)
        val phase = parameters.braidTwist * x +
            parameters.braidIrregularity * sin(x / 53 + bendPhase * 0.7f) +
            parameters.curl * getFlare(x) + braidPhase + strandIndex * 2 * PI.toFloat() / count
        val y = center + strandRadius * sin(phase)
        out[0] = parameters.heightLimit * tanh(y / parameters.heightLimit)
        out[1] = cos(phase)
    }

    /** 1 in the birth zone at the Stop circle, 0 away from it */
    fun getFlare(x: Float): Float =
        1 - smoothStep(-6f, 3 * parameters.flareLength, VIEW_ORIGIN + stopCenter - STOP_RADIUS - x)

    private fun end(newEnding: Ending) {
        isRecording = false
        ending = newEnding
    }

    private fun updateLevels(level: Float, deltaTime: Float) {
        val gate = parameters.gate
        val target = (max(0f, level - gate) / (1 - gate)).pow(parameters.gamma)
        val fastTime = if (isReduceMotion) {
            if (target > fastLevel) 0.15f else 0.45f
        } else {
            if (target > fastLevel) parameters.attack else parameters.release
        }
        fastLevel += (target - fastLevel) * (1 - exp(-deltaTime / fastTime))
        // A sharper level than `fastLevel`, so separate syllables travel along the ribbon
        val syllableTime = when {
            isReduceMotion -> 0.3f
            target > syllableLevel -> SYLLABLE_ATTACK
            else -> parameters.syllableRelease
        }
        syllableLevel += (target - syllableLevel) * (1 - exp(-deltaTime / syllableTime))
        val slowTime = if (fastLevel > slowLevel) parameters.slowAttack else parameters.slowRelease
        slowLevel += (fastLevel - slowLevel) * (1 - exp(-deltaTime / slowTime))
    }

    // Phases are integrated rather than computed from time, so a change of speed never makes them jump
    private fun advanceClocks(deltaTime: Float) {
        if (isReduceMotion) return
        val fullTurn = 2 * PI.toFloat()
        val braidSpeed = parameters.braidSpeedAtRest + parameters.braidSpeedGrowth * fastLevel
        braidPhase = (braidPhase + deltaTime * braidSpeed) % fullTurn
        silkPhase = (silkPhase + deltaTime * parameters.silkSpeed * (1 + 2 * fastLevel)) % fullTurn
        bendPhase += deltaTime * parameters.bendSpeed * (1 + 3 * slowLevel)
        breathTime += deltaTime
    }

    // A critically damped spring that settles within the transition's duration. With animations off the thread
    // shows and goes at once.
    private fun updatePresence(deltaTime: Float) {
        val desaturationTarget = if (!isRecording && ending == Ending.CANCEL) 1f else 0f
        if (isReduceMotion) {
            presence = if (isRecording) 1f else 0f
            presenceVelocity = 0f
            desaturation = desaturationTarget
            return
        }
        val duration = when {
            isRecording -> parameters.startDuration
            ending == Ending.STOP -> parameters.stopDuration
            ending == Ending.CANCEL -> parameters.cancelDuration
            else -> parameters.sendDuration
        }
        val frequency = 4.6f / duration
        val offset = presence - if (isRecording) 1 else 0
        val acceleration = -frequency * frequency * offset - 2 * frequency * presenceVelocity
        presenceVelocity += acceleration * deltaTime
        presence = (presence + presenceVelocity * deltaTime).coerceIn(0f, 1f)
        val desaturationTime = max(0.03f, parameters.cancelDuration * 0.3f)
        val desaturationShare = 1 - exp(-deltaTime / desaturationTime)
        desaturation += (desaturationTarget - desaturation) * desaturationShare
    }

    private fun recordHistory(deltaTime: Float) {
        historyAge += deltaTime
        while (historyAge >= SAMPLE_INTERVAL) {
            historyAge -= SAMPLE_INTERVAL
            System.arraycopy(history, 0, history, 1, HISTORY_COUNT - 1)
        }
        history[0] = syllableLevel
    }

    // The shader's section on iOS at ribbon x
    private fun makeSection(x: Float, transition: Transition): Section {
        val stopRim = VIEW_ORIGIN + stopCenter - STOP_RADIUS
        val ribbonLength = stopRim - FAR_END
        val fromStop = stopRim - x
        val along = (fromStop / ribbonLength).coerceIn(0f, 1f)
        val level = if (isReduceMotion) 0f else readHistory(along * parameters.syllableDelay)
        val nearEnd = stopRim - STOP_GAP
        val fade = smoothStep(FAR_END, FAR_END + parameters.fadeLength, x) *
            (1 - smoothStep(nearEnd - parameters.fadeLength, nearEnd, x))
        val tip = transition.reveal * (ribbonLength + 30) - 8
        val visibility = 1 - smoothStep(tip - 24, tip, fromStop)
        val flare = 1 - smoothStep(-6f, 3 * parameters.flareLength, fromStop)
        var radius = if (isReduceMotion) {
            parameters.braidRadiusAtRest + 0.25f * parameters.braidRadiusGrowth
        } else {
            val breathing = 1 + parameters.breath * sin(breathTime * 1.1f - along * 5)
            parameters.braidRadiusAtRest * breathing +
                parameters.braidRadiusGrowth * max(level, 0f).pow(0.8f)
        }
        val flareRadius =
            parameters.braidRadiusAtRest + parameters.flare * (0.35f + 0.65f * fastLevel)
        radius = mix(radius, flareRadius, flare * 0.85f)
        val taper = mix(1f, 1 - parameters.taper, smoothStep(0.1f, 1f, along))
        radius *= taper * mix(0.25f, 1f, fade) * visibility * (1 - transition.slide)
        val bend = parameters.bend * (1 + 1.5f * slowLevel) *
            getWave(x / parameters.bendLength + bendPhase)
        val center = bend * smoothStep(0f, 40f, fromStop) * fade
        return Section(center, radius, level, fade * visibility)
    }

    // The syllable level `age` seconds ago, smoothed over neighbouring samples so fast attacks bend without kinks
    private fun readHistory(age: Float): Float {
        val spacing = 1.6f / 60
        val sum = readHistorySample(max(age - 2 * spacing, 0f)) +
            4 * readHistorySample(max(age - spacing, 0f)) +
            6 * readHistorySample(age) +
            4 * readHistorySample(age + spacing) +
            readHistorySample(age + 2 * spacing)
        return sum / 16
    }

    private fun readHistorySample(age: Float): Float {
        var position = if (age >= historyAge) {
            (age - historyAge) * 60 + 1
        } else {
            age / max(historyAge, 0.0001f)
        }
        position = position.coerceIn(0f, HISTORY_COUNT - 1 - 0.001f)
        val index = position.toInt()
        return mix(history[index], history[index + 1], position - index)
    }

    private enum class Ending { STOP, CANCEL, SEND }

    data class Transition(
        /** How far the thread is drawn out of the Stop circle */
        val reveal: Float,
        val opacity: Float,
        /** How far the thread has slid into the Send pill */
        val slide: Float
    )

    private data class Section(
        val center: Float,
        val radius: Float,
        val level: Float,
        val opacity: Float
    )

    companion object {
        /** The Stop circle is as wide as the field's buttons, 40 dp */
        const val STOP_RADIUS = 20f

        /** The ✕ button's trailing edge in the field: a 4 dp inset and the 40 dp button */
        private const val CROSS_END = 44f

        /** The view's leading edge: the strip starts the field's 8 dp text gap after the ✕ button */
        const val VIEW_ORIGIN = CROSS_END + 8

        /** Ribbon x of the far end, 12 dp after the ✕ button */
        const val FAR_END = CROSS_END + 12

        /** The thread fades out this far before the Stop circle, as far as it starts after the ✕ button */
        const val STOP_GAP = FAR_END - CROSS_END
        private const val HISTORY_COUNT = 64
        private const val SAMPLE_INTERVAL = 1f / 60
        private const val SYLLABLE_ATTACK = 0.025f

        // Longer frames, such as after a stall, advance the ribbon by this much only
        private const val MAX_DELTA_TIME = 0.05f
        private const val FINISHED_PRESENCE = 0.002f

        // Below it a new recording starts from silence
        private const val COLD_START_PRESENCE = 0.05f
    }
}

/**
 * The accent's palette for the ribbon in OKLCH: a deep colour, the core, a lighter glow and almost white highlights,
 * with hues spread around the accent's. A grey accent gets a silver palette.
 */
internal fun makeAgentVoiceRibbonPalette(
    accent: Int,
    isDark: Boolean,
    parameters: AgentVoiceRibbonParameters
): AgentVoiceRibbonPalette {
    val (lightness, chroma, hue) = convertToOklch(accent)
    val isGrey = chroma < 0.025
    val chromaScale = parameters.chroma.toDouble()
    val spread = parameters.hueSpread.toDouble()

    fun scaleChroma(factor: Double) =
        if (isGrey) chroma else min(chroma * factor * chromaScale, chroma + 0.04 * chromaScale)

    if (isDark) {
        val shift = parameters.darkLightness.toDouble()
        return AgentVoiceRibbonPalette(
            deep = makeColor(
                (lightness - 0.06 + shift).coerceIn(0.42, 0.62),
                scaleChroma(1.0),
                hue - spread
            ),
            core = makeColor(
                (lightness + 0.075 + shift).coerceIn(0.60, 0.76),
                scaleChroma(1.0),
                hue
            ),
            glow = makeColor(
                (lightness + 0.225 + shift).coerceIn(0.75, 0.90),
                scaleChroma(0.87),
                hue + 0.6 * spread
            ),
            hot = makeColor(0.96, min(chroma * 0.30, 0.05), hue + 1.2 * spread)
        )
    }
    val shift = parameters.lightLightness.toDouble()
    return AgentVoiceRibbonPalette(
        deep = makeColor(
            (lightness - 0.07 + shift).coerceIn(0.38, 0.56),
            scaleChroma(1.05),
            hue - spread
        ),
        core = makeColor((lightness + 0.02 + shift).coerceIn(0.50, 0.66), scaleChroma(1.05), hue),
        glow = makeColor(
            (lightness + 0.17 + shift).coerceIn(0.68, 0.84),
            scaleChroma(0.9),
            hue + 0.6 * spread
        ),
        hot = makeColor(0.985, min(chroma * 0.20, 0.03), hue + 1.2 * spread)
    )
}

// Lightness, chroma and hue in degrees
private fun convertToOklch(color: Int): Triple<Double, Double, Double> {
    val red = convertToLinear(Color.red(color) / 255.0)
    val green = convertToLinear(Color.green(color) / 255.0)
    val blue = convertToLinear(Color.blue(color) / 255.0)
    val long = cbrt(0.4122214708 * red + 0.5363325363 * green + 0.0514459929 * blue)
    val medium = cbrt(0.2119034982 * red + 0.6806995451 * green + 0.1073969566 * blue)
    val short = cbrt(0.0883024619 * red + 0.2817188376 * green + 0.6299787005 * blue)
    val lightness = 0.2104542553 * long + 0.7936177850 * medium - 0.0040720468 * short
    val greenRed = 1.9779984951 * long - 2.4285922050 * medium + 0.4505937099 * short
    val blueYellow = 0.0259040371 * long + 0.7827717662 * medium - 0.8086757660 * short
    val chroma = sqrt(greenRed * greenRed + blueYellow * blueYellow)
    return Triple(lightness, chroma, atan2(blueYellow, greenRed) * 180 / PI)
}

// An sRGB colour of the given OKLCH. Out of gamut the chroma shrinks and the lightness and hue stay.
private fun makeColor(lightness: Double, chroma: Double, hue: Double): Int {
    var currentChroma = chroma
    repeat(GAMUT_STEP_COUNT) {
        val linear = convertToLinearSrgb(lightness, currentChroma, hue)
        if (linear.all { it >= -0.001 && it <= 1.001 }) return encodeSrgb(linear)
        currentChroma *= 0.92
    }
    return encodeSrgb(convertToLinearSrgb(lightness, 0.0, hue))
}

private fun convertToLinearSrgb(lightness: Double, chroma: Double, hue: Double): DoubleArray {
    val angle = hue * PI / 180
    val greenRed = chroma * cos(angle)
    val blueYellow = chroma * sin(angle)
    val longRoot = lightness + 0.3963377774 * greenRed + 0.2158037573 * blueYellow
    val mediumRoot = lightness - 0.1055613458 * greenRed - 0.0638541728 * blueYellow
    val shortRoot = lightness - 0.0894841775 * greenRed - 1.2914855480 * blueYellow
    val long = longRoot * longRoot * longRoot
    val medium = mediumRoot * mediumRoot * mediumRoot
    val short = shortRoot * shortRoot * shortRoot
    return doubleArrayOf(
        4.0767416621 * long - 3.3077115913 * medium + 0.2309699292 * short,
        -1.2684380046 * long + 2.6097574011 * medium - 0.3413193965 * short,
        -0.0041960863 * long - 0.7034186147 * medium + 1.7076147010 * short
    )
}

private fun encodeSrgb(linear: DoubleArray): Int = Color.rgb(
    (convertToGamma(linear[0].coerceIn(0.0, 1.0)) * 255).roundToInt(),
    (convertToGamma(linear[1].coerceIn(0.0, 1.0)) * 255).roundToInt(),
    (convertToGamma(linear[2].coerceIn(0.0, 1.0)) * 255).roundToInt()
)

private fun convertToLinear(value: Double) =
    if (value <= 0.04045) value / 12.92 else ((value + 0.055) / 1.055).pow(2.4)

private fun convertToGamma(value: Double) =
    if (value <= 0.0031308) 12.92 * value else 1.055 * value.pow(1 / 2.4) - 0.055

// A smooth wave of three incommensurate sines, from -1 to 1, as in the shader
private fun getWave(t: Float): Float =
    0.55f * sin(t + 0.3f) + 0.30f * sin(2.13f * t + 1.1f) + 0.15f * sin(3.71f * t + 2.0f)

private fun tanh(value: Float): Float {
    val square = exp(2 * value.coerceIn(-10f, 10f))
    return (square - 1) / (square + 1)
}

// GLSL's `smoothstep`
private fun smoothStep(edge0: Float, edge1: Float, x: Float): Float {
    val t = ((x - edge0) / (edge1 - edge0)).coerceIn(0f, 1f)
    return t * t * (3 - 2 * t)
}

private fun mix(from: Float, to: Float, amount: Float) = from + (to - from) * amount

private const val GAMUT_STEP_COUNT = 30
