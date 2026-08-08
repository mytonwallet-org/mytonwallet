package org.mytonwallet.app_air.uisend.send

import java.math.BigDecimal
import java.math.BigInteger
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.mytonwallet.app_air.walletbasecontext.models.MBaseCurrency
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.moshi.IApiToken

class SendViewModelInputTest {

    @Test
    fun maxKeepsExactTokenAmountInBaseCurrencyMode() {
        val maxAmount = BigInteger("123456789")
        val equivalent = SendViewModel.InputStateRaw(
            tokenSlug = "test",
            amount = "0.123456789",
            amountInBaseCurrency = "0.01",
            fiatMode = true,
            isMax = true
        ).resolveAmountEquivalent(
            tokenPrice = BigDecimal("3"),
            token = token(),
            baseCurrency = MBaseCurrency.USD
        )

        assertEquals(maxAmount, equivalent.tokenAmount.amountInteger)
    }

    @Test
    fun baseCurrencyInputRemainsSourceInTokenMode() {
        val input = SendViewModel.InputStateRaw(
            tokenSlug = "test",
            amountInBaseCurrency = "0.2",
            fiatMode = true,
            amountSource = SendViewModel.AmountSource.BASE_CURRENCY
        )

        val equivalent = input.resolveAmountEquivalent(
            tokenPrice = BigDecimal("3"),
            token = token(),
            baseCurrency = MBaseCurrency.USD
        )

        assertEquals(BigInteger("66666666"), equivalent.tokenAmount.amountInteger)
        val equivalentAtNewPrice = input.resolveAmountEquivalent(
            tokenPrice = BigDecimal("6"),
            token = token(),
            baseCurrency = MBaseCurrency.USD
        )
        assertEquals(BigInteger("33333333"), equivalentAtNewPrice.tokenAmount.amountInteger)

        val tokenModeInput = input.updateOtherAmount(equivalentAtNewPrice).copy(fiatMode = false)
        assertEquals("0.033333333", tokenModeInput.displayedAmount)
        val restoredBaseCurrencyInput = tokenModeInput.copy(fiatMode = true)
        assertEquals("0.2", restoredBaseCurrencyInput.displayedAmount)

        val snapshottedEquivalentAtNewPrice =
            tokenModeInput.resolveAmountEquivalent(
                tokenPrice = BigDecimal("12"),
                token = token(),
                baseCurrency = MBaseCurrency.USD
            )
        assertEquals(
            BigInteger("33333333"),
            snapshottedEquivalentAtNewPrice.tokenAmount.amountInteger
        )
        assertEquals(
            BigInteger("20"),
            snapshottedEquivalentAtNewPrice.currencyAmount.amountInteger
        )
    }

    @Test
    fun tokenInputRemainsSourceInBaseCurrencyMode() {
        val input = SendViewModel.InputStateRaw(
            tokenSlug = "test",
            amount = "0.2",
            fiatMode = false
        )

        val equivalent = input.resolveAmountEquivalent(
            tokenPrice = BigDecimal("3"),
            token = token(),
            baseCurrency = MBaseCurrency.USD
        )

        assertEquals(BigInteger("200000000"), equivalent.tokenAmount.amountInteger)
        val equivalentAtNewPrice = input.resolveAmountEquivalent(
            tokenPrice = BigDecimal("6"),
            token = token(),
            baseCurrency = MBaseCurrency.USD
        )
        assertEquals(
            BigInteger("120"),
            equivalentAtNewPrice.currencyAmount.amountInteger
        )

        val baseCurrencyModeInput = input.updateOtherAmount(
            equivalentAtNewPrice
        ).copy(fiatMode = true)
        assertEquals("1.2", baseCurrencyModeInput.displayedAmount)
        assertEquals("0.2", baseCurrencyModeInput.copy(fiatMode = false).displayedAmount)

        val snapshottedEquivalentAtNewPrice = baseCurrencyModeInput.resolveAmountEquivalent(
            tokenPrice = BigDecimal("9"),
            token = token(),
            baseCurrency = MBaseCurrency.USD
        )
        assertEquals(
            BigInteger("120"),
            snapshottedEquivalentAtNewPrice.currencyAmount.amountInteger
        )
    }

    @Test
    fun chainChangeUsesSelectedWalletAddressForNewChain() {
        val account = account(
            mapOf(
                "ton" to "ton-address",
                "ethereum" to "ethereum-address"
            )
        )

        val destination = SendViewModel.resolveDestinationForChainChange(
            destination = "ton-address",
            previousChain = "ton",
            nextChain = "ethereum",
            accounts = listOf(account)
        )

        assertEquals("ethereum-address", destination)
    }

    @Test
    fun chainChangeUsesExactSelectedWalletWhenAddressesAreShared() {
        val firstAccount = account(
            accountId = "first-account",
            name = "First Wallet",
            addresses = mapOf(
                "ton" to "shared-ton-address",
                "ethereum" to "first-ethereum-address"
            )
        )
        val secondAccount = account(
            accountId = "second-account",
            name = "Second Wallet",
            addresses = mapOf(
                "ton" to "shared-ton-address",
                "ethereum" to "second-ethereum-address"
            )
        )

        val destination = SendViewModel.resolveDestinationForChainChange(
            destination = "shared-ton-address",
            destinationAccountId = "second-account",
            previousChain = "ton",
            nextChain = "ethereum",
            accounts = listOf(firstAccount, secondAccount)
        )

        assertEquals("second-ethereum-address", destination)
        assertEquals(
            "second-account",
            SendViewModel.findDestinationAccount(
                destination = "shared-ton-address",
                chain = "ton",
                preferredAccountId = "second-account",
                accounts = listOf(firstAccount, secondAccount)
            )?.accountId
        )
    }

    @Test
    fun accountLookupDoesNotFallbackWhenSelectedWalletDoesNotMatch() {
        val account = account(
            accountId = "first-account",
            addresses = mapOf("ton" to "shared-ton-address")
        )

        assertNull(
            SendViewModel.findDestinationAccount(
                destination = "shared-ton-address",
                chain = "ton",
                preferredAccountId = "second-account",
                accounts = listOf(account)
            )
        )
    }

    @Test
    fun chainChangeKeepsRecipientWhenItIsNotAnotherWallet() {
        val destination = SendViewModel.resolveDestinationForChainChange(
            destination = "external-address",
            previousChain = "ton",
            nextChain = "ethereum",
            accounts = listOf(account(mapOf("ton" to "ton-address")))
        )

        assertEquals("external-address", destination)
    }

    @Test
    fun chainChangeKeepsRecipientWhenWalletDoesNotSupportNewChain() {
        val destination = SendViewModel.resolveDestinationForChainChange(
            destination = "ton-address",
            previousChain = "ton",
            nextChain = "ethereum",
            accounts = listOf(account(mapOf("ton" to "ton-address")))
        )

        assertEquals("ton-address", destination)
    }

    private fun token() = object : IApiToken {
        override val slug = "test"
        override val decimals = 9
        override val name: String? = "Test"
        override val symbol: String? = "TEST"
        override val chain: String? = null
        override val tokenAddress: String? = null
        override val image: String? = null
        override val isPopular: Boolean? = null
        override val keywords: List<String>? = null
    }

    private fun account(
        addresses: Map<String, String>,
        accountId: String = "account-id",
        name: String = "Wallet"
    ) = MAccount(
        accountId = accountId,
        byChain = addresses.mapValues { MAccount.AccountChain(address = it.value) },
        name = name,
        accountType = MAccount.AccountType.MNEMONIC,
        importedAt = null,
        isTemporary = false
    )
}
