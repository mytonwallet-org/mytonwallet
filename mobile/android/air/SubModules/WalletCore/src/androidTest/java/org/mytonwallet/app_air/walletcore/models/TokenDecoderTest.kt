package org.mytonwallet.app_air.walletcore.models

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.squareup.moshi.JsonDataException
import com.squareup.moshi.JsonReader
import okio.Buffer
import org.json.JSONException
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.mytonwallet.app_air.walletbasecontext.utils.ApplicationContextHolder

@RunWith(AndroidJUnit4::class)
class TokenDecoderTest {
    @Before
    fun setUp() {
        ApplicationContextHolder.update(InstrumentationRegistry.getInstrumentation().targetContext)
    }

    @Test
    fun skipsMalformedTokensWithoutLosingTheFollowingToken() {
        for (invalid in listOf(
            "null",
            "[]",
            """{"priceUsd":1e999}""",
            """{"future":{"value":1e999}}"""
        )) {
            assertThrows(JSONException::class.java) { MToken(JSONObject(invalid)) }
            JsonReader.of(Buffer().writeUtf8("[$invalid,{\"slug\":\"valid\"}]")).use { reader ->
                reader.beginArray()
                assertThrows(JsonDataException::class.java) { readToken(reader) }
                assertEquals("valid", readToken(reader).slug)
                reader.endArray()
            }
        }
    }

    @Test
    fun matchesLegacyDecodingForCompletePartialAndIrregularTokens() {
        val fixtures = listOf(
            """{}""",
            """{"slug":"toncoin","chain":"ton","decimals":9,"symbol":"TON","name":"Toncoin","image":"image","priceUsd":5.125,"percentChange24h":-1.235,"keywords":["ton","wallet"],"isPopular":true,"isFromBackend":true,"isGaslessEnabled":true,"isStarsEnabled":true,"isTiny":true,"type":"lp_token","label":"token","codeHash":"hash","cmcSlug":"toncoin","color":"#ffffff","customPayloadApiUrl":"https://example.invalid"}""",
            """{"minterAddress":" ","tokenAddress":"fallback","chain":"","blockchain":"tron","localizedName":" ","color":null,"decimals":"6.8","priceUsd":"NaN","percentChange24h":"Infinity","isPopular":"TRUE"}""",
            """{"slug":null,"name":null,"image":null,"tokenAddress":null,"minterAddress":null,"chain":null,"keywords":[null,true,1,1.5,{"x":1},[1,null]]}""",
            """{"slug":"trc20:EQ","name":1e3,"symbol":false,"codeHash":9223372036854775807,"decimals":4294967296,"priceUsd":"broken","percentChange24h":null,"keywords":"wrong"}""",
            """{"name":{"nested":[1,2,null]},"name":"last","extra":{"deep":[1,2,3]}}"""
        )
        for (fixture in fixtures) {
            val expected = MToken(JSONObject(fixture))
            val actual = JsonReader.of(Buffer().writeUtf8(fixture)).use(::readToken)
            assertEquals(
                fixture,
                expected.toDictionary().toString(),
                actual.toDictionary().toString()
            )
            assertEquals(expected.percentChange24h, actual.percentChange24h, 0.0)
            assertEquals(expected.priceUsd, actual.priceUsd, 0.0)
            assertEquals(expected.mBlockchain, actual.mBlockchain)
        }
    }
}
