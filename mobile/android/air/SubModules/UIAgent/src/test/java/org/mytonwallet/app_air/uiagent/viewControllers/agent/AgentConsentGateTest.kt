package org.mytonwallet.app_air.uiagent.viewControllers.agent

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Job
import kotlinx.coroutines.joinAll
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentConsentGateTest {
    private class Sheet {
        var asked = 0
        var allow: (() -> Unit)? = null
        var decline: (() -> Unit)? = null
    }

    private fun createGate(
        consent: () -> Boolean?,
        stored: Boolean = false,
        sheet: Sheet,
        onAllowed: () -> Unit = {}
    ) = AgentConsentGate(
        knownConsent = consent,
        readConsent = { stored },
        askForConsent = { allow, decline ->
            sheet.asked++
            sheet.allow = allow
            sheet.decline = decline
        },
        onAllowed = onAllowed
    )

    @Test
    fun anAllowedAgentTakesTheActionWithoutTheSheet() = runBlocking {
        val sheet = Sheet()
        var sent = 0
        createGate(consent = { true }, sheet = sheet).request { sent++ }

        assertEquals(1, sent)
        assertEquals(0, sheet.asked)
    }

    @Test
    fun allowCarriesOutTheHeldActionOnce() = runBlocking {
        val sheet = Sheet()
        var consent: Boolean? = false
        var sent = 0
        val gate = createGate(consent = { consent }, sheet = sheet, onAllowed = { consent = true })

        gate.request { sent++ }
        assertEquals(1, sheet.asked)
        assertEquals(0, sent)

        sheet.allow!!()
        assertEquals(1, sent)
        // The consent stays: the next action goes at once
        gate.request { sent++ }
        assertEquals(2, sent)
        assertEquals(1, sheet.asked)
    }

    @Test
    fun closingTheSheetDropsTheActionAndTheNextOneAsksAgain() = runBlocking {
        val sheet = Sheet()
        var sent = 0
        val gate = createGate(consent = { false }, sheet = sheet)

        gate.request { sent++ }
        sheet.decline!!()
        assertEquals(0, sent)

        gate.request { sent++ }
        assertEquals(2, sheet.asked)
        assertEquals(0, sent)
    }

    @Test
    fun onlyClosingTheSheetHandsTheFocusBack() = runBlocking {
        val sheet = Sheet()
        var consent: Boolean? = false
        var refocused = 0
        val gate = createGate(consent = { consent }, sheet = sheet, onAllowed = { consent = true })

        gate.request(onDeclined = { refocused++ }) {}
        sheet.decline!!()
        assertEquals(1, refocused)

        gate.request(onDeclined = { refocused++ }) {}
        sheet.allow!!()
        assertEquals(1, refocused)
    }

    @Test
    fun anActionWhileTheSheetShowsAsksNoSecondSheet() = runBlocking {
        val sheet = Sheet()
        var sent = 0
        val gate = createGate(consent = { false }, sheet = sheet)

        gate.request { sent++ }
        gate.request { sent += 10 }
        assertEquals(1, sheet.asked)

        sheet.allow!!()
        assertEquals(1, sent)
    }

    @Test
    fun aConsentNotYetKnownIsReadBeforeAsking() = runBlocking {
        val sheet = Sheet()
        var allowedCount = 0
        var sent = 0
        createGate(
            consent = { null },
            stored = true,
            sheet = sheet,
            onAllowed = { allowedCount++ }
        ).request { sent++ }

        assertEquals(1, sent)
        assertEquals(1, allowedCount)
        assertEquals(0, sheet.asked)
    }

    @Test
    fun aDictationHeldForConsentStartsOnAllowAndNotWhenTheSheetCloses() {
        val sheet = Sheet()
        var isAwaitingConsent = true
        var started = 0
        val shouldHoldDictation = holdDictationForConsent(
            isAwaitingConsent = { isAwaitingConsent },
            heldDictation = AgentHeldDictation(),
            askForConsent = { allow, decline ->
                sheet.asked++
                sheet.allow = allow
                sheet.decline = decline
            },
            startDictation = { started++ }
        )

        assertTrue(shouldHoldDictation())
        assertEquals(1, sheet.asked)
        assertEquals(0, started)
        // Declining, or dismissing the sheet, leaves the microphone off
        sheet.decline!!()
        assertEquals(0, started)

        assertTrue(shouldHoldDictation())
        sheet.allow!!()
        assertEquals(1, started)

        // With consent, the press records at once, without the sheet
        isAwaitingConsent = false
        assertFalse(shouldHoldDictation())
        assertEquals(2, sheet.asked)
        assertEquals(1, started)
    }

    @Test
    fun aDictationHeldWhileTheConsentIsReadStartsOnlyIfTheScreenStayed() = runBlocking {
        var read = CompletableDeferred<Boolean>()
        var allowedCount = 0
        var started = 0
        val heldDictation = AgentHeldDictation()
        val requests = mutableListOf<Job>()
        val gate = AgentConsentGate(
            knownConsent = { null },
            readConsent = { read.await() },
            askForConsent = { _, _ -> },
            onAllowed = { allowedCount++ }
        )
        val shouldHoldDictation = holdDictationForConsent(
            isAwaitingConsent = { true },
            heldDictation = heldDictation,
            askForConsent = { allow, decline ->
                requests += launch(start = CoroutineStart.UNDISPATCHED) {
                    gate.request(decline, allow)
                }
            },
            startDictation = { started++ }
        )

        // The screen goes while the consent is read, and doesn't record once it is allowed, back or not
        assertTrue(shouldHoldDictation())
        heldDictation.drop()
        read.complete(true)
        requests.joinAll()
        assertEquals(1, allowedCount)
        assertEquals(0, started)

        read = CompletableDeferred()
        assertTrue(shouldHoldDictation())
        heldDictation.drop()
        // Back on the screen before the read answers, a press waits on the same read
        assertTrue(shouldHoldDictation())
        read.complete(true)
        requests.joinAll()
        assertEquals(2, allowedCount)
        assertEquals(0, started)

        // On a screen that stays, the read allowing records once, however many presses waited
        read = CompletableDeferred()
        assertTrue(shouldHoldDictation())
        assertTrue(shouldHoldDictation())
        read.complete(true)
        requests.joinAll()
        assertEquals(3, allowedCount)
        assertEquals(1, started)
    }
}
