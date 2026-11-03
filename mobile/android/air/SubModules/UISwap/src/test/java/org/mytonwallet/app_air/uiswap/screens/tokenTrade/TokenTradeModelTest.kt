package org.mytonwallet.app_air.uiswap.screens.tokenTrade

import java.lang.reflect.Proxy
import java.math.BigInteger
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.AfterClass
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.BeforeClass
import org.junit.Test
import org.mytonwallet.app_air.uiswap.screens.swap.models.SwapInputState
import org.mytonwallet.app_air.uiswap.screens.swap.models.SwapUiInputState
import org.mytonwallet.app_air.uiswap.screens.swap.models.SwapWalletState
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.localization.WLanguage
import org.mytonwallet.app_air.walletbasecontext.models.MBaseCurrency
import org.mytonwallet.app_air.walletcontext.globalStorage.IGlobalStorageProvider
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.IApiToken
import org.mytonwallet.app_air.walletcore.stores.AccountStore

class TokenTradeModelTest {
    private var previousAccount: MAccount? = null

    @Before
    fun setUp() {
        previousAccount = AccountStore.activeAccount
        AccountStore.activeAccount = MAccount(
            accountId = ACCOUNT_ID,
            byChain = mapOf(MBlockchain.ton.name to MAccount.AccountChain(TON_ADDRESS)),
            name = "Test",
            accountType = MAccount.AccountType.MNEMONIC,
            importedAt = null,
            isTemporary = false
        )
    }

    @After
    fun tearDown() {
        AccountStore.activeAccount = previousAccount
    }

    @Test
    fun sellAllKeepsMaximumWhenReceivedTokenChanges() {
        val swap = FakeSwap()
        val model = sellModel(swap)

        model.useFraction(100)
        model.selectToken(OTHER)
        assertEquals(MAX_CALL, swap.amountCalls.last())

        model.selectToken(USDT)
        assertEquals(MAX_CALL, swap.amountCalls.last())
    }

    @Test
    fun typedSellAmountSurvivesReceivedTokenChange() {
        val swap = FakeSwap()
        val model = sellModel(swap)

        model.userEditedInput(TokenTradeAmountInput.of(tons(5), TON.decimals))
        model.selectToken(OTHER)

        assertEquals("send:5", swap.amountCalls.last())
    }

    @Test
    fun sellAllFitsCardMaximumAfterSwitchingToCard() = runBlocking {
        val model = sellModel(FakeSwap())

        model.useFraction(100)
        model.selectCard(MBaseCurrency.EUR)
        assertFalse(model.canContinue)
        assertNotEquals(insufficientBalance(), model.actionTitle)

        assertTrue(model.refreshCardMaximum(model.cardMaximumRequest()!!))
        assertEquals(CARD_MAXIMUM, model.typedTokenAmount)
        assertNotEquals(insufficientBalance(), model.actionTitle)
        assertTrue(model.canContinue)
    }

    @Test
    fun typedCardAmountAboveMaximumIsInsufficient() = runBlocking {
        val model = sellModel(FakeSwap())

        model.selectCard(MBaseCurrency.EUR)
        assertTrue(model.refreshCardMaximum(model.cardMaximumRequest()!!))
        model.userEditedInput(TokenTradeAmountInput.of(BALANCE, TON.decimals))

        assertEquals(insufficientBalance(), model.actionTitle)
        assertFalse(model.canContinue)
    }

    @Test
    fun cardSellAllKeepsMaximumWhenSwitchingToToken() = runBlocking {
        val swap = FakeSwap()
        val model = sellModel(swap)

        model.selectCard(MBaseCurrency.EUR)
        assertTrue(model.refreshCardMaximum(model.cardMaximumRequest()!!))
        model.useFraction(100)
        model.selectToken(OTHER)

        assertEquals(MAX_CALL, swap.amountCalls.last())
    }

    private fun sellModel(swap: FakeSwap): TokenTradeModel = TokenTradeModel(
        swap,
        TokenTradeDirection.SELL,
        TON,
        loadCardMaximum = { _, _, _ -> CARD_MAXIMUM }
    ).apply { update(state = swap.currentUiInputState) }

    private fun insufficientBalance(): String = LocaleController.getString("Insufficient Balance")

    private class FakeSwap : TokenTradeSwap {
        val amountCalls = mutableListOf<String>()
        private var tokenToReceive: IApiToken? = USDT

        override val tokenToSendMaxBalance: BigInteger = BALANCE

        override val currentUiInputState: SwapUiInputState
            get() = SwapUiInputState(
                SwapWalletState(
                    ACCOUNT_ID,
                    mapOf(MBlockchain.ton.name to TON_ADDRESS),
                    mapOf(TON.slug to BALANCE),
                    emptyList()
                ),
                SwapInputState(tokenToSend = TON, tokenToReceive = tokenToReceive)
            )

        override fun tokenToSendSetMaxAmount() {
            amountCalls += MAX_CALL
        }

        override fun onTokenToSendAmountInput(amount: CharSequence?) {
            amountCalls += "send:$amount"
        }

        override fun onTokenToReceiveAmountInput(amount: CharSequence?) {
            amountCalls += "receive:$amount"
        }

        override fun setTokenToSend(asset: IApiToken) =
            error("Selling never changes the sent token")

        override fun setTokenToReceive(asset: IApiToken?) {
            tokenToReceive = asset
        }
    }

    private class TestToken(
        override val slug: String,
        override val symbol: String,
        override val decimals: Int
    ) : IApiToken {
        override val name: String = symbol
        override val chain: String = MBlockchain.ton.name
        override val tokenAddress: String? = null
        override val image: String? = null
        override val isPopular: Boolean? = null
        override val keywords: List<String>? = null
    }

    companion object {
        private const val ACCOUNT_ID = "0-mainnet"
        private const val TON_ADDRESS = "UQBvW8Z5huBkMJYdnfAEM5JqTNkuWX3diqYENkWsIL0XggGG"
        private const val MAX_CALL = "max"
        private val TON = TestToken(MBlockchain.ton.nativeSlug, "TON", 9)
        private val USDT = TestToken("ton-eqcxe6mutq", "USDT", 6)
        private val OTHER = TestToken("ton-eqavlwfdxg", "OTHER", 9)
        private val BALANCE = tons(10)
        private val CARD_MAXIMUM = BALANCE - BigInteger.valueOf(5_000_000)

        private var previousLanguage: WLanguage? = null
        private var previousStorage: Any? = null

        private fun tons(amount: Long): BigInteger =
            BigInteger.valueOf(amount).multiply(BigInteger.TEN.pow(9))

        private val storageField = WGlobalStorage::class.java.getDeclaredField(
            "globalStorageProvider"
        )
            .apply { isAccessible = true }

        private val languageField = LocaleController::class.java.getDeclaredField("_activeLanguage")
            .apply { isAccessible = true }

        @JvmStatic
        @BeforeClass
        fun initializeEmptyWalletStorage() {
            previousLanguage = languageField.get(null) as WLanguage?
            languageField.set(null, WLanguage.ENGLISH)
            previousStorage = storageField.get(WGlobalStorage)
            val storage = Proxy.newProxyInstance(
                IGlobalStorageProvider::class.java.classLoader,
                arrayOf(IGlobalStorageProvider::class.java)
            ) { _, method, _ ->
                when (method.name) {
                    "contains" -> false

                    "keysIn" -> emptyArray<String>()

                    "getInt", "getString", "getBool", "getDict", "getArray",
                    "incrementDoNotSynchronize", "decrementDoNotSynchronize",
                    "set", "setEmptyObject", "setEmptyObjects", "remove" -> null

                    else -> error("Unexpected wallet storage call: ${method.name}")
                }
            } as IGlobalStorageProvider
            WGlobalStorage.init(storage)
        }

        @JvmStatic
        @AfterClass
        fun restoreGlobals() {
            languageField.set(null, previousLanguage)
            storageField.set(WGlobalStorage, previousStorage)
        }
    }
}
