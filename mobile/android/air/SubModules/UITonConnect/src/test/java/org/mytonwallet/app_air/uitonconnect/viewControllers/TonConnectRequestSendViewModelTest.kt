package org.mytonwallet.app_air.uitonconnect.viewControllers

import java.math.BigInteger
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.mytonwallet.app_air.uicomponents.adapter.implementation.Item
import org.mytonwallet.app_air.walletcore.moshi.ApiDapp
import org.mytonwallet.app_air.walletcore.moshi.ApiDappTransfer
import org.mytonwallet.app_air.walletcore.moshi.MSignDataPayload
import org.mytonwallet.app_air.walletcore.moshi.api.ApiUpdate

class TonConnectRequestSendViewModelTest {
    private val dapp = ApiDapp(
        url = "https://example.com",
        name = "Example",
        iconUrl = null,
        manifestUrl = "https://example.com/tonconnect-manifest.json",
        connectedAt = null
    )

    private fun transfer(stateInit: String? = null, isDangerous: Boolean = false) = ApiDappTransfer(
        toAddress = "message-address",
        amount = BigInteger.ONE,
        stateInit = stateInit,
        isDangerous = isDangerous,
        normalizedAddress = "message-address",
        displayedToAddress = "message-address",
        networkFee = BigInteger.ZERO
    )

    private fun request(vararg transactions: ApiDappTransfer) =
        ApiUpdate.ApiUpdateDappSendTransactions(
            promiseId = "promise-id",
            accountId = "account-id",
            dapp = dapp,
            operationChain = "ton",
            transactions = transactions.toList()
        )

    @Test
    fun `request with a state init warns about signing unless the payload warning is shown`() {
        val stateInit = transfer(stateInit = "te6cckEBAQEAAgAAAEysuc0=")

        assertEquals("\$signature_warning", requestWarningKey(request(transfer(), stateInit)))
        assertEquals(
            "\$hardware_payload_warning",
            requestWarningKey(request(transfer(isDangerous = true), stateInit))
        )
        assertNull(requestWarningKey(request(transfer(), transfer(stateInit = ""))))
    }

    @Test
    fun `message details show the state init and pick the warning like the request does`() {
        val stateInit = transfer(stateInit = "te6cckEBAQEAAgAAAEysuc0=")
        val items = stateInitUiItems(stateInit)

        assertEquals(
            listOf("Contract Initialization Data"),
            items.filterIsInstance<Item.ListTitle>().map { it.title.toString() }
        )
        assertEquals(
            "te6cckEBAQEAAgAAAEysuc0=",
            items.filterIsInstance<Item.ExpandableText>().single().text
        )
        assertTrue(items.filterIsInstance<Item.Alert>().isEmpty())
        assertTrue(stateInitUiItems(transfer()).isEmpty())

        assertEquals("\$signature_warning", messageWarningKey(stateInit))
        assertEquals(
            "\$hardware_payload_warning",
            messageWarningKey(transfer(stateInit = "te6cckEBAQEAAgAAAEysuc0=", isDangerous = true))
        )
        assertNull(messageWarningKey(transfer(stateInit = "")))
    }

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
