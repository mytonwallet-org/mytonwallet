package org.mytonwallet.app_air.uiagent.agentV2

import kotlin.coroutines.Continuation
import kotlin.coroutines.resume
import kotlin.coroutines.suspendCoroutine
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.yield
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2TranscriptionResponse

// A few of the controller's 80 ms samples
private const val TICKS_MS = 250L

class AgentDictationControllerTest {
    @Test
    fun hiddenDraftRejectsInsertionDeletionAndReplacementUntilDictationIsIdle() {
        val draft = "draft"
        listOf(
            Triple(AgentDictationPhase.PRESSING, 0, 0),
            Triple(AgentDictationPhase.RECORDING, 1, 3),
            Triple(AgentDictationPhase.RECOGNIZING, 0, draft.length)
        ).forEach { (phase, start, end) ->
            val replacement = AgentDictationState(phase).filterDraftEdit(draft, start, end)
            assertEquals(draft, draft.replaceRange(start, end, checkNotNull(replacement)))
        }
        assertNull(AgentDictationState().filterDraftEdit(draft, 0, draft.length))
        assertNull(
            AgentDictationState(AgentDictationPhase.FAILED).filterDraftEdit(draft, 0, draft.length)
        )
    }

    @Test
    fun slidingLeftCancelsTheRecordingWithoutCallingTheAgent() = runBlocking {
        val fixture = Fixture(this)
        fixture.controller.press()
        fixture.started.await()

        fixture.controller.move(
            horizontalDp = -150f,
            upDp = 0f,
            cancelDirection = AgentDictationCancelDirection.LEFT
        )
        fixture.recorder.cancelled.await()

        assertEquals(AgentDictationPhase.IDLE, fixture.controller.state.phase)
        assertTrue(fixture.failures.isEmpty())
        assertEquals(0, fixture.apiCalls)
        assertEquals(0, fixture.recorder.finishCalls)
    }

    @Test
    fun releasingFastTowardTheStartCancelsWhileAShortReleaseTranscribes() = runBlocking {
        val cancelling = Fixture(this)
        cancelling.controller.press()
        cancelling.started.await()
        cancelling.now = 1000

        cancelling.controller.release(
            horizontalDp = -40f,
            upDp = 10f,
            horizontalVelocity = -500f,
            cancelDirection = AgentDictationCancelDirection.LEFT
        )
        cancelling.recorder.cancelled.await()

        assertEquals(AgentDictationPhase.IDLE, cancelling.controller.state.phase)
        assertEquals(0, cancelling.apiCalls)

        val finishing = Fixture(this)
        finishing.controller.press()
        finishing.started.await()
        finishing.now = 1000

        finishing.controller.release(
            horizontalDp = -40f,
            upDp = 10f,
            horizontalVelocity = -100f,
            cancelDirection = AgentDictationCancelDirection.LEFT
        )
        finishing.recorder.cancelled.await()

        assertEquals(1, finishing.apiCalls)
        assertEquals(listOf("Text"), finishing.transcripts)
    }

    @Test
    fun slidingRightInRtlCancelsWithoutCallingTheAgentWhileSlidingLeftDoesNot() = runBlocking {
        val fixture = Fixture(this)
        fixture.controller.press()
        fixture.started.await()

        fixture.controller.move(
            horizontalDp = -150f,
            upDp = 0f,
            cancelDirection = AgentDictationCancelDirection.RIGHT
        )

        assertEquals(AgentDictationPhase.RECORDING, fixture.controller.state.phase)
        assertEquals(-150f, fixture.controller.state.cancelDragDp, 0f)

        fixture.controller.move(
            horizontalDp = 150f,
            upDp = 0f,
            cancelDirection = AgentDictationCancelDirection.RIGHT
        )
        fixture.recorder.cancelled.await()

        assertEquals(AgentDictationPhase.IDLE, fixture.controller.state.phase)
        assertTrue(fixture.failures.isEmpty())
        assertEquals(0, fixture.apiCalls)
        assertEquals(0, fixture.recorder.finishCalls)
    }

    @Test
    fun recordingShorterThanMinimumIsDiscardedBeforeEncodingOrCallingTheAgent() = runBlocking {
        val fixture = Fixture(this)
        fixture.controller.startHandsFree()
        fixture.started.await()
        fixture.now = 699

        fixture.controller.finish()
        fixture.recorder.cancelled.await()

        assertEquals(AgentDictationPhase.FAILED, fixture.controller.state.phase)
        assertEquals(listOf(AgentDictationFailure.TooShort), fixture.failures)
        assertEquals(0, fixture.apiCalls)
        assertEquals(0, fixture.recorder.finishCalls)
    }

    @Test
    fun recordingWithoutSpeechIsDiscardedBeforeEncodingOrCallingTheAgent() = runBlocking {
        val fixture = Fixture(this, amplitude = 999)
        fixture.controller.startHandsFree()
        fixture.started.await()
        fixture.now = 1000

        fixture.controller.finish()
        fixture.recorder.cancelled.await()

        assertEquals(AgentDictationPhase.FAILED, fixture.controller.state.phase)
        assertEquals(listOf(AgentDictationFailure.NoSpeech), fixture.failures)
        assertEquals(0, fixture.apiCalls)
        assertEquals(0, fixture.recorder.finishCalls)
    }

    @Test
    fun cancelledRecognitionDiscardsANonCooperativeLateTranscript() = runBlocking {
        val recognizing = CompletableDeferred<Unit>()
        lateinit var response: Continuation<AgentV2TranscriptionResponse>
        val operationParent = Job(coroutineContext[Job])
        val fixture = Fixture(CoroutineScope(coroutineContext + operationParent), transcribe = {
            suspendCoroutine { continuation ->
                response = continuation
                recognizing.complete(Unit)
            }
        })
        fixture.controller.startHandsFree()
        fixture.started.await()
        fixture.now = 1000
        fixture.controller.finish()
        recognizing.await()

        fixture.controller.cancel()
        response.resume(AgentV2TranscriptionResponse("transcribed", "Late text"))
        operationParent.complete()
        operationParent.join()

        assertEquals(1, fixture.apiCalls)
        assertEquals(AgentDictationPhase.IDLE, fixture.controller.state.phase)
        assertTrue(fixture.transcripts.isEmpty())
        assertTrue(fixture.failures.isEmpty())
    }

    @Test
    fun releasingWhilePermissionIsPendingDiscardsANonCooperativeLateGrant() = runBlocking {
        val permissionRequested = CompletableDeferred<Unit>()
        lateinit var permissionResult: Continuation<Boolean>
        val operationParent = Job(coroutineContext[Job])
        val fixture = Fixture(
            CoroutineScope(coroutineContext + operationParent),
            requestPermission = {
                suspendCoroutine { continuation ->
                    permissionResult = continuation
                    permissionRequested.complete(Unit)
                }
            }
        )
        fixture.controller.press()
        permissionRequested.await()
        fixture.now = 220

        fixture.controller.release()
        permissionResult.resume(true)
        operationParent.complete()
        operationParent.join()

        assertEquals(AgentDictationPhase.IDLE, fixture.controller.state.phase)
        assertEquals(0, fixture.recorder.startCalls)
        assertEquals(0, fixture.apiCalls)
        assertTrue(fixture.failures.isEmpty())
    }

    @Test
    fun appBackgroundOnlyPreservesHandsFreeAttemptsAwaitingPermission() = runBlocking {
        listOf(false, true).forEach { handsFree ->
            val permissionRequested = CompletableDeferred<Unit>()
            lateinit var permissionResult: Continuation<Boolean>
            val operationParent = Job(coroutineContext[Job])
            val fixture = Fixture(
                CoroutineScope(coroutineContext + operationParent),
                requestPermission = {
                    suspendCoroutine { continuation ->
                        permissionResult = continuation
                        permissionRequested.complete(Unit)
                    }
                }
            )
            if (handsFree) fixture.controller.startHandsFree() else fixture.controller.press()
            permissionRequested.await()

            fixture.controller.onAppBackground()

            assertEquals(
                if (handsFree) AgentDictationPhase.PRESSING else AgentDictationPhase.IDLE,
                fixture.controller.state.phase
            )
            permissionResult.resume(true)
            if (handsFree) {
                fixture.started.await()
                assertEquals(AgentDictationPhase.RECORDING, fixture.controller.state.phase)
                assertTrue(fixture.controller.state.locked)
                fixture.controller.cancel()
            }
            operationParent.complete()
            operationParent.join()

            assertEquals(if (handsFree) 1 else 0, fixture.recorder.startCalls)
            assertEquals(0, fixture.apiCalls)
            assertTrue(fixture.failures.isEmpty())
        }
    }

    @Test
    fun lockedRecordingSurvivesReleaseAndTheLimitTranscribesOnce() = runBlocking {
        val fixture = Fixture(this)
        fixture.controller.press()
        fixture.started.await()
        fixture.now = 1000
        fixture.controller.move(
            horizontalDp = 0f,
            upDp = 110f,
            cancelDirection = AgentDictationCancelDirection.LEFT
        )

        fixture.controller.release(upDp = 110f)
        yield()

        assertEquals(AgentDictationPhase.RECORDING, fixture.controller.state.phase)
        assertTrue(fixture.controller.state.locked)
        assertEquals(0, fixture.recorder.finishCalls)
        assertEquals(0, fixture.apiCalls)

        fixture.now = 60_000
        fixture.recorder.cancelled.await()

        assertEquals(AgentDictationPhase.IDLE, fixture.controller.state.phase)
        assertEquals(1, fixture.recorder.finishCalls)
        assertEquals(1, fixture.apiCalls)
        assertEquals(listOf("Text"), fixture.transcripts)
        assertTrue(fixture.failures.isEmpty())
    }

    @Test
    fun pausedRecordingStopsItsTimeAndResumesTheSameRecording() = runBlocking {
        val fixture = Fixture(this)
        fixture.controller.startHandsFree()
        fixture.started.await()
        fixture.now = 1000

        fixture.controller.pause()
        assertTrue(fixture.controller.state.isPaused)
        assertEquals(1000, fixture.controller.state.elapsedMs)

        // A pause doesn't count toward the limit
        fixture.now = 61_000
        delay(TICKS_MS)
        assertEquals(AgentDictationPhase.RECORDING, fixture.controller.state.phase)
        assertEquals(1000, fixture.controller.state.elapsedMs)
        assertEquals(0, fixture.recorder.finishCalls)

        fixture.controller.resume()
        fixture.now = 61_500
        delay(TICKS_MS)
        assertEquals(1500, fixture.controller.state.elapsedMs)

        fixture.controller.pause()
        fixture.controller.finish()
        fixture.recorder.cancelled.await()

        assertEquals(1, fixture.recorder.startCalls)
        assertEquals(2, fixture.recorder.pauseCalls)
        assertEquals(1, fixture.recorder.resumeCalls)
        assertEquals(1, fixture.recorder.finishCalls)
        assertEquals(listOf("Text"), fixture.transcripts)
        assertTrue(fixture.failures.isEmpty())
    }

    @Test
    fun cancellingDuringEncodingReleasesTheRecorderAndOldCleanupCannotCancelTheNewOne() =
        runBlocking {
            val encodingStarted = CompletableDeferred<Unit>()
            lateinit var encodedAudio: Continuation<String>
            lateinit var controller: AgentDictationController
            val firstRecorder = EncodingRecorder(encode = {
                suspendCoroutine { continuation ->
                    encodedAudio = continuation
                    encodingStarted.complete(Unit)
                }
            })
            val secondRecorder = EncodingRecorder()
            val recorders = listOf(firstRecorder, secondRecorder)
            val recorderIterator = recorders.iterator()
            val transcripts = mutableListOf<String>()
            val operationParent = Job(coroutineContext[Job])
            var now = 0L
            var apiCalls = 0
            controller = AgentDictationController(
                scope = CoroutineScope(coroutineContext + operationParent),
                recorderFactory = { recorderIterator.next() },
                requestPermission = { true },
                transcribe = {
                    apiCalls++
                    AgentV2TranscriptionResponse("transcribed", "Text")
                },
                nowMs = { now },
                onStateChanged = {},
                onTranscript = transcripts::add,
                onFailure = { throw AssertionError(it.toString()) }
            )
            controller.startHandsFree()
            firstRecorder.started.await()
            now = 1000
            controller.finish()
            encodingStarted.await()
            val firstOperation = operationParent.children.single()

            controller.cancel()

            assertEquals(AgentDictationPhase.IDLE, controller.state.phase)
            assertEquals(1, firstRecorder.cancelCalls)
            controller.startHandsFree()
            secondRecorder.started.await()
            assertEquals(AgentDictationPhase.RECORDING, controller.state.phase)

            encodedAudio.resume("encoded audio")
            firstOperation.join()

            assertEquals(1, firstRecorder.cancelCalls)
            assertEquals(0, secondRecorder.cancelCalls)
            assertEquals(AgentDictationPhase.RECORDING, controller.state.phase)
            assertEquals(0, apiCalls)
            assertTrue(transcripts.isEmpty())

            controller.cancel()
            operationParent.complete()
            operationParent.join()
            assertEquals(1, secondRecorder.cancelCalls)
        }

    private class Fixture(
        scope: CoroutineScope,
        amplitude: Int = 2000,
        requestPermission: suspend () -> Boolean = { true },
        transcribe: suspend () -> AgentV2TranscriptionResponse = {
            AgentV2TranscriptionResponse("transcribed", "Text")
        }
    ) {
        var now = 0L
        var apiCalls = 0
        val failures = mutableListOf<AgentDictationFailure>()
        val transcripts = mutableListOf<String>()
        val started = CompletableDeferred<Unit>()
        val recorder = FakeRecorder(amplitude)
        val controller = AgentDictationController(
            scope = scope,
            recorderFactory = { recorder },
            requestPermission = requestPermission,
            transcribe = {
                apiCalls++
                transcribe()
            },
            nowMs = { now },
            onStateChanged = {},
            onTranscript = transcripts::add,
            onFailure = failures::add,
            onRecordingStarted = { started.complete(Unit) }
        )
    }

    private class FakeRecorder(private val amplitude: Int) : AgentDictationRecorder {
        val cancelled = CompletableDeferred<Unit>()
        var startCalls = 0
        var finishCalls = 0
        var pauseCalls = 0
        var resumeCalls = 0

        override fun start() {
            startCalls++
        }

        override fun amplitude() = amplitude

        override fun pause() {
            pauseCalls++
        }

        override fun resume() {
            resumeCalls++
        }

        override suspend fun finish(): String {
            finishCalls++
            return "audio"
        }

        override fun cancel() {
            cancelled.complete(Unit)
        }
    }

    private class EncodingRecorder(private val encode: suspend () -> String = { "audio" }) :
        AgentDictationRecorder {
        val started = CompletableDeferred<Unit>()
        var cancelCalls = 0

        override fun start() {
            started.complete(Unit)
        }

        override fun amplitude() = 2000

        override fun pause() = Unit

        override fun resume() = Unit

        override suspend fun finish() = encode()

        override fun cancel() {
            cancelCalls++
        }
    }
}
