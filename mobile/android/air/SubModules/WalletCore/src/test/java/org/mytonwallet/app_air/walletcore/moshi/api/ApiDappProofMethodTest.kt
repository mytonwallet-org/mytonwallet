package org.mytonwallet.app_air.walletcore.moshi.api

import org.junit.Assert.assertEquals
import org.junit.Test
import org.mytonwallet.app_air.walletcore.moshi.MoshiBuilder

class ApiDappProofMethodTest {
    private val moshi = MoshiBuilder.build()

    @Test
    fun signDappProofResultDecodesPublicKeys() {
        val result = moshi.adapter(ApiMethod.DApp.SignDappProof.Result::class.java)
            .fromJson("""{"signatures":["signature"],"publicKeys":["public-key"]}""")

        assertEquals(listOf("signature"), result?.signatures)
        assertEquals(listOf("public-key"), result?.publicKeys)
    }

    @Test
    fun confirmDappRequestConnectEncodesProofPublicKeys() {
        val request = ApiMethod.DApp.ConfirmDappRequestConnect.Request(
            accountId = "account",
            proofSignatures = listOf("signature"),
            proofPublicKeys = listOf("public-key")
        )

        val json = moshi
            .adapter(ApiMethod.DApp.ConfirmDappRequestConnect.Request::class.java)
            .toJson(request)

        assertEquals(
            """{"accountId":"account","proofSignatures":["signature"],"proofPublicKeys":["public-key"]}""",
            json
        )
    }
}
