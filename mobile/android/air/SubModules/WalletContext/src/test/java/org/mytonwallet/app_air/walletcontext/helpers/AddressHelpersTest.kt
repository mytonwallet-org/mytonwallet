package org.mytonwallet.app_air.walletcontext.helpers

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AddressHelpersTest {

    private val validAddress = "UQBFz01R2CU7YA8pevUaNIYyi5jyeGKb9KGdKUrfLQPTJC_1" // 48 chars

    // isValidAddress

    @Test
    fun acceptsWellFormed48CharAddress() {
        assertEquals(48, validAddress.length)
        assertTrue(AddressHelpers.isValidAddress(validAddress))
    }

    @Test
    fun rejectsWrongLengthWhenExactLengthRequired() {
        assertFalse(AddressHelpers.isValidAddress(validAddress.dropLast(1)))
        assertFalse(AddressHelpers.isValidAddress(validAddress + "A"))
        assertFalse(AddressHelpers.isValidAddress(""))
    }

    @Test
    fun allowsShorterInputWhenExactLengthNotRequired() {
        assertTrue(AddressHelpers.isValidAddress(validAddress.dropLast(10), exactLength = false))
        // Still rejects anything longer than 48
        assertFalse(AddressHelpers.isValidAddress(validAddress + "A", exactLength = false))
    }

    @Test
    fun rejectsIllegalCharacters() {
        assertFalse(AddressHelpers.isValidAddress(validAddress.dropLast(1) + "+"))
        assertFalse(AddressHelpers.isValidAddress(validAddress.dropLast(1) + "/"))
        assertFalse(AddressHelpers.isValidAddress(validAddress.dropLast(1) + " "))
        assertFalse(AddressHelpers.isValidAddress(validAddress.dropLast(1) + "!"))
    }

    // isFriendly

    @Test
    fun friendlyFormAllowsBase64Chars() {
        assertTrue(AddressHelpers.isFriendly(validAddress))
        assertTrue(AddressHelpers.isFriendly("E" + "Q".repeat(45) + "+/"))
    }

    @Test
    fun friendlyFormRequiresExactly48Chars() {
        assertFalse(AddressHelpers.isFriendly(validAddress.dropLast(1)))
        assertFalse(AddressHelpers.isFriendly(validAddress + "A"))
    }

    @Test
    fun friendlyBounceableDetectedByPrefix() {
        assertTrue(AddressHelpers.isFriendlyAddressBounceable("EQAbc"))
        assertFalse(AddressHelpers.isFriendlyAddressBounceable("UQAbc"))
    }

    // walletInvoiceUrl — builds ton://transfer deeplinks

    @Test
    fun invoiceUrlWithoutParams() {
        assertEquals(
            "ton://transfer/$validAddress",
            AddressHelpers.walletInvoiceUrl(validAddress)
        )
    }

    @Test
    fun invoiceUrlEncodesComment() {
        assertEquals(
            "ton://transfer/$validAddress?text=hello+world",
            AddressHelpers.walletInvoiceUrl(validAddress, comment = "hello world")
        )
        // Characters with URL semantics must not survive raw
        assertEquals(
            "ton://transfer/$validAddress?text=a%26b%3Dc%3Fd",
            AddressHelpers.walletInvoiceUrl(validAddress, comment = "a&b=c?d")
        )
    }

    @Test
    fun invoiceUrlAppendsJettonAndAmount() {
        assertEquals(
            "ton://transfer/$validAddress?text=hi&jetton=JETTON&amount=1000",
            AddressHelpers.walletInvoiceUrl(
                validAddress,
                comment = "hi",
                jetton = "JETTON",
                amount = "1000"
            )
        )
    }

    @Test
    fun invoiceUrlUsesQuestionMarkOnlyForFirstParam() {
        assertEquals(
            "ton://transfer/$validAddress?amount=42",
            AddressHelpers.walletInvoiceUrl(validAddress, amount = "42")
        )
    }
}
