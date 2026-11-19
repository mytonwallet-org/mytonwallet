package org.mytonwallet.app_air.uiagent.agentV2

import kotlin.math.log10
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Job
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2TranscriptionResponse

internal const val AGENT_DICTATION_MAX_DURATION_MS = 60_000L

// A held microphone slid this far toward the field's cross cancels on release, and this far toward
// Send sends; let go nearer its place, its transcript goes into the field
private const val AGENT_DICTATION_CANCEL_ZONE_DP = 90f
private const val AGENT_DICTATION_SEND_ZONE_DP = 24f

internal interface AgentDictationRecorder {
    fun start()

    /** The peak amplitude since the last call, out of 32767 */
    fun amplitude(): Int
    suspend fun finish(): String
    fun cancel()
}

internal enum class AgentDictationPhase {
    IDLE,

    /** The finger is down, or a hands-free recording waits for the microphone */
    PRESSING,
    RECORDING,
    RECOGNIZING,

    /** A recording that produced no transcript, shown for a moment before the microphone returns */
    FAILED
}

/** Why a recording produced no transcript */
internal sealed interface AgentDictationFailure {
    data object TooShort : AgentDictationFailure
    data object NoSpeech : AgentDictationFailure
    data object MicrophoneDenied : AgentDictationFailure
    data class Error(val code: String?) : AgentDictationFailure
}

/**
 * Where letting go of a held microphone takes the recording: its transcript into the field where
 * the finger started, nowhere at the field's cross, and off as the question at Send
 */
internal enum class AgentDictationHoldZone {
    STOP,
    CANCEL,
    SEND
}

internal enum class AgentDictationCancelDirection(val sign: Int) {
    LEFT(-1),
    RIGHT(1)
}

internal data class AgentDictationState(
    val phase: AgentDictationPhase = AgentDictationPhase.IDLE,
    val locked: Boolean = false,
    /** The time recorded so far */
    val elapsedMs: Long = 0,
    val level: Float = 0f,
    /** How far the recording waves swell, from 0 to 1: Telegram's peak amplitude against 16000 */
    val waveLevel: Float = 0f,
    /** The voice's peak amplitude since the last sample, from 0 to 1, which the hands-free thread spins with */
    val peakLevel: Float = 0f,
    /** The recording being recognized goes as the question once it is text, rather than into the field */
    val isSending: Boolean = false,
    /** The recording has heard speech, so there is something to recognize and send */
    val hasSpeech: Boolean = false,
    /** The finger's travel toward cancelling, negative toward Send */
    val cancelDragDp: Float = 0f,
    /** The finger's travel up, which no gesture uses any more */
    val lockDragDp: Float = 0f,
    val holdZone: AgentDictationHoldZone = AgentDictationHoldZone.STOP,
    val failure: AgentDictationFailure? = null
) {
    /** The field shows the recording instead of the draft */
    val isActive: Boolean
        get() = phase == AgentDictationPhase.PRESSING || phase == AgentDictationPhase.RECORDING ||
            phase == AgentDictationPhase.RECOGNIZING
}

/**
 * Hold-to-talk dictation: a hold starts recording, and where the finger lets go decides by
 * [AgentDictationHoldZone]: into the draft, cancelled, or sent. A tap records hands-free until
 * Stop, into the draft, or Send.
 */
internal class AgentDictationController(
    private val scope: CoroutineScope,
    private val recorderFactory: () -> AgentDictationRecorder,
    private val requestPermission: suspend () -> Boolean,
    private val transcribe: suspend (String) -> AgentV2TranscriptionResponse,
    private val nowMs: () -> Long,
    private val onStateChanged: (AgentDictationState) -> Unit,
    private val onTranscript: (String) -> Unit,
    /** A transcript to send as the question at once */
    private val onSendTranscript: (String) -> Unit = onTranscript,
    private val onFailure: (AgentDictationFailure) -> Unit = {},
    private val onRecordingStarted: () -> Unit = {},
    /** The finger crosses where letting go would cancel or lock, or the recording locks */
    private val onGestureFeedback: () -> Unit = {}
) {
    var state = AgentDictationState()
        private set

    private var operation: Job? = null
    private var failureReset: Job? = null
    private var currentRecorder: AgentDictationRecorder? = null
    private var finishSignal: CompletableDeferred<Boolean>? = null
    private var pendingCancelDragDp = 0f
    private var isSendingTranscript = false
    private var recordingStartedAtMs = 0L

    fun press() {
        if (state.phase != AgentDictationPhase.IDLE && state.phase != AgentDictationPhase.FAILED) {
            return
        }
        endFailure()
        pendingCancelDragDp = 0f
        start(locked = false)
    }

    fun startHandsFree() {
        if (state.phase != AgentDictationPhase.IDLE && state.phase != AgentDictationPhase.FAILED) {
            return
        }
        endFailure()
        start(locked = true)
    }

    /** The recording circle follows the finger along the field, which decides what letting go does */
    fun move(horizontalDp: Float, upDp: Float, cancelDirection: AgentDictationCancelDirection) {
        if (state.locked) return
        pendingCancelDragDp = horizontalDp * cancelDirection.sign
        if (state.phase == AgentDictationPhase.RECORDING) applyMove()
    }

    private fun applyMove() {
        val zone = getHoldZone(pendingCancelDragDp)
        // A light tap marks each change of what letting go would do
        if (zone != state.holdZone) onGestureFeedback()
        update(state.copy(cancelDragDp = pendingCancelDragDp, lockDragDp = 0f, holdZone = zone))
    }

    private fun getHoldZone(cancelTravel: Float): AgentDictationHoldZone = when {
        cancelTravel >= AGENT_DICTATION_CANCEL_ZONE_DP -> AgentDictationHoldZone.CANCEL
        -cancelTravel >= AGENT_DICTATION_SEND_ZONE_DP -> AgentDictationHoldZone.SEND
        else -> AgentDictationHoldZone.STOP
    }

    /**
     * The finger lifts after [horizontalDp] and [upDp] of travel, moving at the given speeds in dp
     * per second. Only the dominant direction counts, as in Telegram.
     */
    fun release(
        horizontalDp: Float = 0f,
        upDp: Float = 0f,
        horizontalVelocity: Float = 0f,
        upVelocity: Float = 0f,
        cancelDirection: AgentDictationCancelDirection = AgentDictationCancelDirection.LEFT
    ) {
        when (state.phase) {
            AgentDictationPhase.PRESSING -> if (!state.locked) cancel()

            AgentDictationPhase.RECORDING -> {
                if (state.locked) return
                when (getHoldZone(horizontalDp * cancelDirection.sign)) {
                    AgentDictationHoldZone.CANCEL -> cancel()
                    AgentDictationHoldZone.SEND -> finish(isSending = true)
                    AgentDictationHoldZone.STOP -> finish()
                }
            }

            else -> Unit
        }
    }

    /** Stops the recording: its transcript goes into the draft, or [isSending] as the question */
    fun finish(isSending: Boolean = false) {
        val stop = finishSignal ?: return
        if (state.phase != AgentDictationPhase.RECORDING || stop.isCompleted) return
        isSendingTranscript = isSending
        stop.complete(false)
    }

    private fun measureElapsed(now: Long): Long =
        (now - recordingStartedAtMs).coerceIn(0L, AGENT_DICTATION_MAX_DURATION_MS)

    fun onAppBackground() {
        if (state.phase == AgentDictationPhase.PRESSING && state.locked) return
        cancel()
    }

    fun cancel() {
        stopEverything()
        update(AgentDictationState())
    }

    private fun stopEverything() {
        val cancelledOperation = operation
        operation = null
        finishSignal = null
        isSendingTranscript = false
        failureReset?.cancel()
        failureReset = null
        releaseRecorder(currentRecorder)
        cancelledOperation?.cancel()
    }

    /** The attempt ends in the failed phase, which returns to idle unless a new touch ends it first */
    private fun fail(failure: AgentDictationFailure) {
        stopEverything()
        update(AgentDictationState(phase = AgentDictationPhase.FAILED, failure = failure))
        onFailure(failure)
        failureReset = scope.launch {
            delay(FAILURE_DURATION_MS)
            failureReset = null
            if (state.phase == AgentDictationPhase.FAILED) update(AgentDictationState())
        }
    }

    private fun endFailure() {
        failureReset?.cancel()
        failureReset = null
        if (state.phase == AgentDictationPhase.FAILED) update(AgentDictationState())
    }

    private fun start(locked: Boolean) {
        update(AgentDictationState(phase = AgentDictationPhase.PRESSING, locked = locked))
        val stop = CompletableDeferred<Boolean>()
        finishSignal = stop
        lateinit var recordingOperation: Job
        recordingOperation = scope.launch(start = CoroutineStart.LAZY) {
            var recorder: AgentDictationRecorder? = null

            // A failure ends this attempt only while it is still the current one
            fun failIfCurrent(failure: AgentDictationFailure) {
                if (operation === recordingOperation) fail(failure)
            }
            try {
                if (!locked) delay(HOLD_DURATION_MS)
                if (!requestPermission()) {
                    currentCoroutineContext().ensureActive()
                    failIfCurrent(AgentDictationFailure.MicrophoneDenied)
                    return@launch
                }
                currentCoroutineContext().ensureActive()
                val activeRecorder = recorderFactory()
                recorder = activeRecorder
                currentRecorder = activeRecorder
                activeRecorder.start()
                currentCoroutineContext().ensureActive()
                recordingStartedAtMs = nowMs()
                var hasSpeech = false
                fun sample() {
                    val amplitude = activeRecorder.amplitude().coerceIn(0, MAX_AMPLITUDE)
                    hasSpeech = hasSpeech || amplitude >= SPEECH_AMPLITUDE
                    val dbfs = 20 * log10(amplitude.coerceAtLeast(1).toDouble() / MAX_AMPLITUDE)
                    val level = ((dbfs + 40) / 36).coerceIn(0.0, 1.0).toFloat()
                    update(
                        state.copy(
                            phase = AgentDictationPhase.RECORDING,
                            elapsedMs = measureElapsed(nowMs()),
                            level = level,
                            waveLevel = (amplitude / FULL_WAVE_AMPLITUDE).coerceIn(0f, 1f),
                            peakLevel = amplitude.toFloat() / MAX_AMPLITUDE,
                            hasSpeech = hasSpeech
                        )
                    )
                }
                sample()
                onRecordingStarted()
                // Where the finger has gone while the recording started
                if (!state.locked) applyMove()
                currentCoroutineContext().ensureActive()
                coroutineScope {
                    val ticker = launch {
                        while (isActive) {
                            sample()
                            if (state.elapsedMs >= AGENT_DICTATION_MAX_DURATION_MS) {
                                stop.complete(true)
                                break
                            }
                            delay(
                                minOf(
                                    POLL_INTERVAL_MS,
                                    AGENT_DICTATION_MAX_DURATION_MS - state.elapsedMs
                                )
                            )
                        }
                    }
                    stop.await()
                    ticker.cancelAndJoin()
                }
                currentCoroutineContext().ensureActive()
                sample()
                if (state.elapsedMs < MIN_DURATION_MS) {
                    releaseRecorder(activeRecorder)
                    failIfCurrent(AgentDictationFailure.TooShort)
                    return@launch
                }
                if (!hasSpeech) {
                    releaseRecorder(activeRecorder)
                    failIfCurrent(AgentDictationFailure.NoSpeech)
                    return@launch
                }
                update(
                    state.copy(
                        phase = AgentDictationPhase.RECOGNIZING,
                        isSending = isSendingTranscript,
                        peakLevel = 0f,
                        cancelDragDp = 0f,
                        lockDragDp = 0f
                    )
                )
                val audio = activeRecorder.finish()
                currentCoroutineContext().ensureActive()
                val response = transcribe(audio)
                currentCoroutineContext().ensureActive()
                releaseRecorder(activeRecorder)
                val transcript = response.text
                if (response.outcome == "no_speech" || transcript.isNullOrBlank()) {
                    failIfCurrent(AgentDictationFailure.NoSpeech)
                } else {
                    operation = null
                    finishSignal = null
                    val isSending = isSendingTranscript
                    isSendingTranscript = false
                    update(AgentDictationState())
                    if (isSending) onSendTranscript(transcript) else onTranscript(transcript)
                }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Throwable) {
                currentCoroutineContext().ensureActive()
                releaseRecorder(recorder)
                failIfCurrent(
                    if (error is SecurityException) {
                        AgentDictationFailure.MicrophoneDenied
                    } else {
                        AgentDictationFailure.Error(
                            (error as? AgentV2OperationException)?.error?.code ?: error.message
                        )
                    }
                )
            } finally {
                releaseRecorder(recorder)
            }
        }
        operation = recordingOperation
        recordingOperation.start()
    }

    private fun releaseRecorder(recorder: AgentDictationRecorder?) {
        if (recorder == null || currentRecorder !== recorder) return
        currentRecorder = null
        runCatching { recorder.cancel() }
    }

    private fun update(newState: AgentDictationState) {
        state = newState
        onStateChanged(newState)
    }

    companion object {
        private const val HOLD_DURATION_MS = 220L
        private const val MIN_DURATION_MS = 700L
        private const val POLL_INTERVAL_MS = 80L
        private const val SPEECH_AMPLITUDE = 1000
        private const val MAX_AMPLITUDE = 32767
        private const val FULL_WAVE_AMPLITUDE = 16000f

        private const val FAILURE_DURATION_MS = 750L
    }
}
