package org.mytonwallet.app_air.walletcore.models

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class MChainDisplayConfigurationTest {

    @Test
    fun defaultConfigurationUsesValueModeAndAutomaticVisibility() {
        val configuration = MChainDisplayConfiguration()
        val orderedChains = configuration.orderedChains(
            accountChainOrder = listOf("ton", "tron", "solana"),
            chainsSortedByValue = listOf("solana", "ton", "tron"),
            chainsShownInValueMode = setOf("ton", "solana")
        )
        val visibleChains = configuration.visibleChains(
            accountChainOrder = listOf("ton", "tron", "solana"),
            orderedChains = orderedChains,
            chainsShownInValueMode = setOf("ton", "solana")
        )

        assertEquals(MChainDisplayMode.VALUE, configuration.displayMode)
        assertTrue(configuration.isDefault)
        assertEquals(listOf("solana", "ton", "tron"), orderedChains)
        assertEquals(listOf("solana", "ton"), visibleChains)
    }

    @Test
    fun unsortedManualOrderKeepsVisibleChainsInValueOrder() {
        val configuration = MChainDisplayConfiguration(displayMode = MChainDisplayMode.MANUAL)

        assertEquals(
            listOf("tron", "ton", "solana", "base", "bnb"),
            configuration.orderedChains(
                accountChainOrder = listOf("ton", "tron", "solana", "base", "bnb"),
                chainsSortedByValue = listOf("tron", "ton", "solana", "base", "bnb")
            )
        )
    }

    @Test
    fun valueModeShowsOnlyChainsWithPortfolioBalance() {
        val configuration = MChainDisplayConfiguration(
            displayMode = MChainDisplayMode.VALUE
        )

        assertEquals(
            listOf("solana", "ton"),
            configuration.visibleChains(
                accountChainOrder = listOf("ton", "tron", "solana"),
                orderedChains = listOf("solana", "ton", "tron"),
                chainsShownInValueMode = setOf("ton", "solana")
            )
        )
    }

    @Test
    fun emptyWalletVisibilityMatchesAppFlavor() {
        val chains = listOf("ethereum", "ton", "tron")

        assertEquals(
            chains.toSet(),
            MChainDisplayConfiguration.chainsShownInValueMode(
                accountChainOrder = chains,
                chainsWithBalance = emptySet(),
                hasTokenBalance = false,
                isGramWallet = false
            )
        )
        assertEquals(
            setOf("ton"),
            MChainDisplayConfiguration.chainsShownInValueMode(
                accountChainOrder = chains,
                chainsWithBalance = emptySet(),
                hasTokenBalance = false,
                isGramWallet = true
            )
        )
    }

    @Test
    fun manualModeStoresOnlyExplicitlyHiddenChains() {
        val configuration = MChainDisplayConfiguration(displayMode = MChainDisplayMode.MANUAL)
        configuration.setVisible("ton", isVisible = false)
        configuration.setVisible("tron", isVisible = true)
        configuration.updateManualOrder(listOf("solana", "ton", "tron"))

        assertEquals(listOf("ton"), configuration.hiddenChains)
        assertEquals(listOf("solana", "ton", "tron"), configuration.manualOrder)
        assertEquals(
            listOf("solana", "tron"),
            configuration.visibleChains(
                accountChainOrder = listOf("ton", "tron", "solana"),
                orderedChains = listOf("solana", "ton", "tron")
            )
        )

        configuration.setVisible("ton", isVisible = true)
        configuration.setVisible("tron", isVisible = false)
        assertEquals(listOf("tron"), configuration.hiddenChains)
        assertEquals(listOf("solana", "ton", "tron"), configuration.manualOrder)
    }

    @Test
    fun manuallyHiddenChainStaysHiddenWhenBalancesChange() {
        val configuration = MChainDisplayConfiguration(
            displayMode = MChainDisplayMode.MANUAL,
            hiddenChains = listOf("tron"),
            manualOrder = listOf("solana", "ton", "tron")
        )

        assertEquals(
            listOf("solana", "ton", "ethereum"),
            configuration.visibleChains(
                accountChainOrder = listOf("ton", "tron", "solana", "ethereum"),
                orderedChains = listOf("solana", "ton", "tron", "ethereum")
            )
        )
    }

    @Test
    fun manualOrderKeepsHiddenChainsInPlace() {
        val configuration = MChainDisplayConfiguration(
            displayMode = MChainDisplayMode.MANUAL,
            hiddenChains = listOf("solana"),
            manualOrder = listOf("solana", "tron", "bnb", "ton", "base")
        )

        assertEquals(
            listOf("solana", "tron", "bnb", "ton", "base", "ethereum"),
            configuration.normalizedManualOrder(
                accountChainOrder = listOf("ton", "tron", "solana", "base", "bnb", "ethereum")
            )
        )
        assertEquals(
            listOf("solana", "tron", "bnb", "ton", "base", "ethereum"),
            configuration.orderedChains(
                accountChainOrder = listOf("ton", "tron", "solana", "base", "bnb", "ethereum"),
                chainsSortedByValue = listOf("bnb", "base")
            )
        )
    }

    @Test
    fun switchingToValueModeClearsManualChoices() {
        val configuration = MChainDisplayConfiguration(
            displayMode = MChainDisplayMode.MANUAL,
            hiddenChains = listOf("ton"),
            manualOrder = listOf("solana", "ton", "tron")
        )

        configuration.updateDisplayMode(MChainDisplayMode.VALUE)

        assertTrue(configuration.hiddenChains.isEmpty())
        assertTrue(configuration.manualOrder.isEmpty())
        assertEquals(MChainDisplayMode.VALUE, configuration.displayMode)
        assertTrue(configuration.isDefault)

        configuration.updateDisplayMode(MChainDisplayMode.MANUAL)

        assertEquals(
            listOf("tron", "ton", "solana"),
            configuration.orderedChains(
                accountChainOrder = listOf("ton", "tron", "solana"),
                chainsSortedByValue = listOf("tron", "ton", "solana")
            )
        )
        assertFalse(configuration.isDefault)
    }

    @Test
    fun changingDefaultDisplayModePersistsOnlyManualChoice() {
        val data = MAssetsAndActivityData()

        data.saveChainDisplayMode(MChainDisplayMode.MANUAL)
        assertEquals(MChainDisplayMode.MANUAL, data.chainDisplayConfiguration?.displayMode)

        data.saveChainDisplayMode(MChainDisplayMode.VALUE)
        assertNull(data.chainDisplayConfiguration)
    }

    @Test
    fun changingVisibilityDoesNotFreezeValueOrder() {
        val configuration = MChainDisplayConfiguration(displayMode = MChainDisplayMode.MANUAL)

        configuration.setVisible("tron", isVisible = true)
        configuration.setVisible("solana", isVisible = false)

        assertTrue(configuration.manualOrder.isEmpty())
        assertEquals(
            listOf("tron", "solana", "ton"),
            configuration.orderedChains(
                accountChainOrder = listOf("ton", "tron", "solana"),
                chainsSortedByValue = listOf("tron", "solana", "ton")
            )
        )
    }

    @Test
    fun invalidAllHiddenStateKeepsFallbackChainVisible() {
        val configuration = MChainDisplayConfiguration(
            displayMode = MChainDisplayMode.MANUAL,
            hiddenChains = listOf("ton", "tron")
        )

        assertEquals(
            listOf("ton"),
            configuration.visibleChains(
                accountChainOrder = listOf("ton", "tron"),
                orderedChains = listOf("tron", "ton")
            )
        )
    }
}
