package org.mytonwallet.app_air.uiswap.screens.tokenTrade

import java.math.BigInteger
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class TokenTradeAmountInputTest {

    private fun input(text: String, decimals: Int = 2): TokenTradeAmountInput =
        TokenTradeAmountInput().replacing(0, 0, text, decimals)!!.input

    @Test
    fun selectionReplacementAndDeletionPreserveCentsAndCaret() {
        val replacement = input("1234.56").replacing(1, 3, "9", 2)!!
        assertEquals("194.56", replacement.input.text)
        assertEquals(BigInteger.valueOf(19_456), replacement.input.amount(2))
        assertEquals(2, replacement.caret)
        val deletion = replacement.input.replacing(1, 2, "", 2)!!
        assertEquals("14.56", deletion.input.text)
        assertEquals(1, deletion.caret)
    }

    @Test
    fun pasteNormalizesLocalizedDigitsAndGroupingWithExactPrecision() {
        val localized = input("١٢ ٣٤٥,٦٧")
        assertEquals("12345.67", localized.text)
        assertEquals(BigInteger.valueOf(1_234_567), localized.amount(2))
        assertEquals("1234.56", input("1,234.56").text)
    }

    @Test
    fun fractionFirstAndLeadingZeroInputAreNormalized() {
        val decimal = TokenTradeAmountInput().replacing(0, 0, ".", 9)!!
        assertEquals("0.", decimal.input.text)
        assertEquals(2, decimal.caret)
        assertEquals("5.10", input("0005.10").text)
        val empty = decimal.input.replacing(0, 2, "", 9)!!
        assertTrue(empty.input.text.isEmpty())
        assertEquals(0, empty.caret)
    }

    @Test
    fun invalidAndOverpreciseEditsLeaveTheAmountUnchanged() {
        val original = input("4.02")
        for (replacement in listOf("9", ".", ",", "-", "e", "🙂")) {
            assertNull(original.replacing(4, 4, replacement, 2))
        }
        assertNull(input("999999999999", decimals = 0).replacing(12, 12, "9", 0))
        assertNull(TokenTradeAmountInput().replacing(0, 0, "1.1", 0))
        assertNull(original.replacing(5, 5, "1", 2))
    }

    @Test
    fun selectedDecimalSeparatorCanBeReplaced() {
        val original = input("4.02")
        val edit = original.replacing(1, 2, ",", 2)!!
        assertEquals(original, edit.input)
        assertEquals(2, edit.caret)
    }

    @Test
    fun tokenPrecisionIsPreservedWithoutFloatingPoint() {
        val amount = BigInteger("123456789012123456789")
        val original = TokenTradeAmountInput.of(amount, 9)
        assertEquals(amount, original.amount(9))
        assertNull(original.replacing(original.text.length, original.text.length, "1", 9))
    }
}
