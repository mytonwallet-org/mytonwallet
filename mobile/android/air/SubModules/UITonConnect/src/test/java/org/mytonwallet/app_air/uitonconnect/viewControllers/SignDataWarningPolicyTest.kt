package org.mytonwallet.app_air.uitonconnect.viewControllers

import org.junit.Assert.assertEquals
import org.junit.Test
import org.mytonwallet.app_air.walletcore.moshi.MSignDataPayload

class SignDataWarningPolicyTest {
    @Test
    fun `every sign data payload shows exactly one generic trust warning`() {
        val payloads = listOf(
            MSignDataPayload.SignDataPayloadText("Message"),
            MSignDataPayload.SignDataPayloadBinary("00"),
            MSignDataPayload.SignDataPayloadEip712(
                domain = emptyMap(),
                types = emptyMap(),
                primaryType = "Message",
                message = emptyMap()
            ),
            cellPayload
        )

        payloads.forEach { payload ->
            assertEquals(
                listOf(SignDataWarningKind.GENERIC_TRUST),
                signDataWarningKinds(payload)
            )
        }
    }

    private val cellPayload = MSignDataPayload.SignDataPayloadCell(
        schema = "root\$_ = Root;",
        cell = "te6ccgEBAQEAAgAAAA=="
    )
}
