package org.mytonwallet.app_air.uiagent.agentV2

import kotlin.math.abs
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
internal const val AGENT_DICTATION_WARNING_START_MS = 50_000L

// Telegram's voice recording gestures: a slide this far toward the start cancels, this far up locks
private const val AGENT_DICTATION_CANCEL_DISTANCE_DP = 150f
private const val AGENT_DICTATION_LOCK_DISTANCE_DP = 110f

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

internal enum class AgentDictationCancelDirection(val sign: Int) {
    LEFT(-1),
    RIGHT(1)
}

internal data class AgentDictationState(
    val phase: AgentDictationPhase = AgentDictationPhase.IDLE,
    val locked: Boolean = false,
    val elapsedMs: Long = 0,
    /** When the recording started, on the controller's clock */
    val startedAtMs: Long = 0,
    val level: Float = 0f,
    /** How far the recording waves swell, from 0 to 1: Telegram's peak amplitude against 16000 */
    val waveLevel: Float = 0f,
    /** The finger's travel toward cancelling, negative away from it */
    val cancelDragDp: Float = 0f,
    /** The finger's travel up, toward locking */
    val lockDragDp: Float = 0f,
    val failure: AgentDictationFailure? = null
) {
    /** The field shows the recording instead of the draft */
    val isActive: Boolean
        get() = phase == AgentDictationPhase.PRESSING || phase == AgentDictationPhase.RECORDING ||
            phase == AgentDictationPhase.RECOGNIZING
}

/**
 * Hold-to-talk dictation after Telegram's voice recording: a hold starts recording, a slide toward
 * the start cancels, a slide up locks it hands-free, and letting go transcribes it into the draft.
 * A transcript never sends by itself.
 */
internal class AgentDictationController(
    private val scope: CoroutineScope,
    private val recorderFactory: () -> AgentDictationRecorder,
    private val requestPermission: suspend () -> Boolean,
    private val transcribe: suspend (String) -> AgentV2TranscriptionResponse,
    private val nowMs: () -> Long,
    private val onStateChanged: (AgentDictationState) -> Unit,
    private val onTranscript: (String) -> Unit,
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
    private var pendingLockDragDp = 0f
    private var hasPassedCancelFeedback = false
    private var hasPassedLockFeedback = false

    fun press() {
        if (state.phase != AgentDictationPhase.IDLE && state.phase != AgentDictationPhase.FAILED) {
            return
        }
        endFailure()
        pendingCancelDragDp = 0f
        pendingLockDragDp = 0f
        hasPassedCancelFeedback = false
        hasPassedLockFeedback = false
        start(locked = false)
    }

    fun startHandsFree() {
        if (state.phase != AgentDictationPhase.IDLE && state.phase != AgentDictationPhase.FAILED) {
            return
        }
        endFailure()
        start(locked = true)
    }

    fun move(horizontalDp: Float, upDp: Float, cancelDirection: AgentDictationCancelDirection) {
        if (state.locked) return
        pendingCancelDragDp = horizontalDp * cancelDirection.sign
        pendingLockDragDp = upDp.coerceAtLeast(0f)
        if (state.phase == AgentDictationPhase.RECORDING) applyMove()
    }

    private fun applyMove() {
        val cancelTravel = pendingCancelDragDp
        val lockTravel = pendingLockDragDp
        when {
            cancelTravel >= AGENT_DICTATION_CANCEL_DISTANCE_DP -> cancel()

            lockTravel >= AGENT_DICTATION_LOCK_DISTANCE_DP -> lock()

            else -> {
                update(state.copy(cancelDragDp = cancelTravel, lockDragDp = lockTravel))
                // A light tap marks the point where letting go would cancel or lock
                val isPastCancel = cancelTravel >= RELEASE_CANCEL_DISTANCE_DP
                if (isPastCancel && !hasPassedCancelFeedback) onGestureFeedback()
                hasPassedCancelFeedback = isPastCancel
                val isPastLock = lockTravel >= RELEASE_LOCK_DISTANCE_DP
                if (isPastLock && !hasPassedLockFeedback) onGestureFeedback()
                hasPassedLockFeedback = isPastLock
            }
        }
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
                val isHorizontal = abs(horizontalDp) > abs(upDp)
                val cancelTravel = horizontalDp * cancelDirection.sign
                val cancelVelocity = horizontalVelocity * cancelDirection.sign
                when {
                    isHorizontal && (
                        cancelVelocity > RELEASE_VELOCITY_DPS ||
                            cancelTravel > RELEASE_CANCEL_DISTANCE_DP
                        ) -> cancel()

                    !isHorizontal && (
                        upVelocity > RELEASE_VELOCITY_DPS || upDp > RELEASE_LOCK_DISTANCE_DP
                        ) -> lock()

                    else -> finish()
                }
            }

            else -> Unit
        }
    }

    private fun lock() {
        hasPassedCancelFeedback = false
        hasPassedLockFeedback = false
        update(state.copy(locked = true, cancelDragDp = 0f, lockDragDp = 0f))
        onGestureFeedback()
    }

    fun finish() {
        if (state.phase == AgentDictationPhase.RECORDING) finishSignal?.complete(false)
    }

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
                val startedAt = nowMs()
                var hasSpeech = false
                fun sample() {
                    val amplitude = activeRecorder.amplitude().coerceIn(0, MAX_AMPLITUDE)
                    hasSpeech = hasSpeech || amplitude >= SPEECH_AMPLITUDE
                    val dbfs = 20 * log10(amplitude.coerceAtLeast(1).toDouble() / MAX_AMPLITUDE)
                    val level = ((dbfs + 40) / 36).coerceIn(0.0, 1.0).toFloat()
                    update(
                        state.copy(
                            phase = AgentDictationPhase.RECORDING,
                            startedAtMs = startedAt,
                            elapsedMs = (nowMs() - startedAt).coerceIn(
                                0L,
                                AGENT_DICTATION_MAX_DURATION_MS
                            ),
                            level = level,
                            waveLevel = (amplitude.toFloat() / FULL_WAVE_AMPLITUDE).coerceIn(0f, 1f)
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
                    update(AgentDictationState())
                    onTranscript(transcript)
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

        // Letting go after this much travel, or this fast, cancels or locks as well
        private const val RELEASE_CANCEL_DISTANCE_DP = 100f
        private const val RELEASE_LOCK_DISTANCE_DP = 60f
        private const val RELEASE_VELOCITY_DPS = 400f
        private const val FAILURE_DURATION_MS = 750L
    }
}
