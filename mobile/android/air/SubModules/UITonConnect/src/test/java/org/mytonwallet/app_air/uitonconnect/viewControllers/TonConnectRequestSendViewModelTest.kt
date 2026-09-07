package org.mytonwallet.app_air.uitonconnect.viewControllers

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.mytonwallet.app_air.uicomponents.adapter.implementation.Item
import org.mytonwallet.app_air.walletcore.moshi.ApiDapp
import org.mytonwallet.app_air.walletcore.moshi.MSignDataPayload
import org.mytonwallet.app_air.walletcore.moshi.api.ApiUpdate

class TonConnectRequestSendViewModelTest {
    @Test
    fun `cell sign data shows parsed preview section exactly once when preview is available`() {
        val update = ApiUpdate.ApiUpdateDappSignData(
            promiseId = "promise-id",
            accountId = "account-id",
            dapp = ApiDapp(
                url = "https://example.com",
                name = "Example",
                iconUrl = null,
                manifestUrl = "https://example.com/tonconnect-manifest.json",
                connectedAt = null
            ),
            operationChain = "ton",
            payloadToSign = MSignDataPayload.SignDataPayloadCell(
                schema = "root\$_ amount:(VarUInteger 16) = Root;",
                cell = "te6ccgEBAQEAAgAAAA=="
            ),
            parsedPayloadToSign = ApiUpdate.ApiUpdateDappSignData.ParsedSignDataCellPreview(
                title = "Root",
                hash = "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef",
                bits = 12,
                refs = 0,
                fields = listOf(
                    ApiUpdate.ApiUpdateDappSignData.ParsedSignDataCellField(
                        label = "amount",
                        value = "9 units",
                        depth = 1
                    )
                ),
                isParsed = true
            )
        )
        val items = buildSignDataUiItems(update)
        val titles = items.filterIsInstance<Item.ListTitle>().map { it.title.toString() }
        val copyableTexts = items.filterIsInstance<Item.CopyableText>()

        assertEquals(1, titles.count { it == "Parsed Cell" })
        assertTrue(titles.contains("Cell Schema"))
        assertTrue(titles.contains("Cell Data"))
        assertEquals(1, copyableTexts.count { it.copyLabel == "Parsed Cell" })
        assertTrue(
            copyableTexts.single { it.copyLabel == "Parsed Cell" }
                .address
                .contains("amount: 9 units")
        )
        assertEquals(1, items.filterIsInstance<Item.Alert>().size)
    }
}
