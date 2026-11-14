package org.mytonwallet.app_air.uiagent.agentV2

import java.math.BigDecimal
import java.math.BigInteger
import java.util.TimeZone
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletbasecontext.utils.ApplicationContextHolder
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.models.MAssetsAndActivityData
import org.mytonwallet.app_air.walletcore.models.MToken
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.ApiNft
import org.mytonwallet.app_air.walletcore.moshi.MApiSwapAsset
import org.mytonwallet.app_air.walletcore.moshi.StakingState
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.AddressStore
import org.mytonwallet.app_air.walletcore.stores.BalanceStore
import org.mytonwallet.app_air.walletcore.stores.NftStore
import org.mytonwallet.app_air.walletcore.stores.StakingStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore

/** What the chat can show, which the SDK declares to the agent; `supportsSupportHandoff` hands a chat to an operator */
internal val AGENT_UI_CAPABILITY_FLAGS = mapOf(
    "supportsFollowups" to true,
    "supportsRunActivity" to false,
    "supportsWalletDirectory" to false,
    "supportsMessageEdit" to true,
    "supportsRegenerate" to true,
    "supportsSupportHandoff" to true
)

/** The chat offers to call a support operator only while it declares the handoff to the agent */
internal val isAgentSupportHandoffDeclared: Boolean
    get() = AGENT_UI_CAPABILITY_FLAGS["supportsSupportHandoff"] == true

internal class AgentHostContextSnapshot(val accountId: String?, val json: JSONObject)

private class AgentV2PositionsProjection(
    val positions: List<JSONObject>,
    val hasNftData: Boolean,
    val hasStakingData: Boolean
)

internal object AgentHostContextBuilder {
    suspend fun build(): AgentHostContextSnapshot {
        val activeAccount = AccountStore.activeAccount
        val activeSavedAddresses = savedAddresses(activeAccount?.accountId)
        // The stores are read here, on the main thread, and copied where they can change; the JSON
        // takes long to build, and is built off the main thread from those copies, TokenStore's
        // concurrent map and its swap list, which is replaced as a whole
        val accountSources = WalletCore.getAllAccounts().map { account ->
            readAccount(
                account,
                if (account.accountId == activeAccount?.accountId) {
                    activeSavedAddresses
                } else {
                    emptyList()
                }
            )
        }
        val baseCurrencyRate = TokenStore.baseCurrencyRate
        val (assets, swapAssetCatalog, accounts) = withContext(Dispatchers.Default) {
            Triple(
                makeAssetCatalog(),
                makeSwapAssetCatalog(),
                accountSources.map { makeAccount(it, baseCurrencyRate) }
            )
        }
        val currencyRate = if (WalletCore.baseCurrency.currencyCode == "USD") {
            "1"
        } else {
            decimalString(baseCurrencyRate?.takeIf { it > 0 })
        }

        val json = JSONObject()
            .put(
                "uiCapabilities",
                JSONObject()
                    .put(
                        "supportedActions",
                        JSONArray(
                            listOf(
                                "send",
                                "receive",
                                "stake",
                                "swap",
                                "openDapp"
                            )
                        )
                    )
                    .apply { AGENT_UI_CAPABILITY_FLAGS.forEach { (key, value) -> put(key, value) } }
            )
            .put("lang", LocaleController.activeLanguage.langCode)
            .put("baseCurrency", WalletCore.baseCurrency.currencyCode)
            .put("currencyRate", currencyRate)
            .put("timeZone", TimeZone.getDefault().id)
            .put("appVersion", ApplicationContextHolder.getAppVersion)
            .put("theme", if (ThemeManager.isDark) "dark" else "light")
            .put("activeAccountId", activeAccount?.accountId)
            .put(
                "activeNetwork",
                // TON when the account has it, else its first network in the app's order, as on web and iOS
                activeAccount?.let { account ->
                    val chains = MBlockchain.supportedChainValues.filter(
                        account.byChain::containsKey
                    )
                    MBlockchain.ton.name.takeIf(chains::contains) ?: chains.firstOrNull()
                }
            )
            .put("isTestnet", activeAccount?.network?.isTestnet)
            .put("isStakingDisabled", activeAccount?.supportsEarn != true)
            .put("accounts", JSONArray(accounts))
            .put("assetCatalog", JSONArray(assets))
            .put("swapAssetCatalog", swapAssetCatalog?.let(::JSONArray))
            .put("savedAddresses", JSONArray(activeSavedAddresses))
            .put("platform", "android")
            .put("client", "native")
        return AgentHostContextSnapshot(activeAccount?.accountId, json)
    }

    private fun makeAssetCatalog() = TokenStore.tokens.values
        .asSequence()
        .filter {
            it.slug.isNotBlank() &&
                it.symbol.isNotBlank() &&
                it.decimals >= 0 &&
                it.chain in MBlockchain.supportedChainValues
        }
        // A catalog over its limit keeps its first assets by slug, the same on every platform and launch
        .sortedBy { it.slug }
        .take(MAX_ASSET_CATALOG_SIZE)
        .map(::makeAsset)
        .toList()

    private fun makeSwapAssetCatalog() = TokenStore.swapAssets
        ?.asSequence()
        ?.sortedBy { it.slug }
        ?.mapNotNull(::makeSwapAsset)
        ?.take(MAX_ASSET_CATALOG_SIZE)
        ?.toList()

    // What an account's context is built from, read on the main thread
    private class AccountSource(
        val account: MAccount,
        val savedAddresses: List<JSONObject>,
        val chains: List<String>,
        val hasBalances: Boolean,
        val holdings: List<HoldingSource>,
        // The account's NFTs, each with whether it is hidden, when they are loaded
        val nfts: List<Pair<ApiNft, Boolean>>?,
        val stakingStates: List<StakingState>?,
        val fullyLoadedChains: List<String>
    )

    private class HoldingSource(val token: MToken, val balance: BigInteger, val isHidden: Boolean)

    private fun readAccount(account: MAccount, savedAddresses: List<JSONObject>): AccountSource {
        val chains = MBlockchain.supportedChainValues.filter(account.byChain::containsKey)
        val balances = BalanceStore.getBalances(account.accountId)?.toMap()
        val assetsAndActivityData = if (account.accountId == AccountStore.activeAccountId) {
            AccountStore.assetsAndActivityData
        } else {
            MAssetsAndActivityData(account.accountId)
        }
        val holdings = balances
            ?.mapNotNull { (slug, balance) ->
                TokenStore.getToken(slug)
                    ?.takeIf {
                        it.chain in chains && it.slug !in assetsAndActivityData.deletedTokens
                    }
                    ?.let { token ->
                        HoldingSource(
                            token,
                            balance,
                            token.isHidden(account, assetsAndActivityData)
                        )
                    }
            }
            .orEmpty()
        val nfts = NftStore.nftData?.takeIf { it.accountId == account.accountId }?.cachedNfts
            ?.map { nft -> nft to NftStore.shouldHide(account.accountId, nft) }
        // Only the active account keeps its NFTs, so another one has no network read in full
        val fullyLoadedChains = if (nfts != null) {
            NftStore.getFullyLoadedChains(account.accountId).map { it.name }
        } else {
            emptyList()
        }
        return AccountSource(
            account = account,
            savedAddresses = savedAddresses,
            chains = chains,
            hasBalances = balances != null,
            holdings = holdings,
            nfts = nfts,
            stakingStates = StakingStore.getStakingState(account.accountId)
                ?.states
                ?.filterNotNull(),
            fullyLoadedChains = fullyLoadedChains
        )
    }

    private fun makeAccount(source: AccountSource, baseCurrencyRate: Double?): JSONObject {
        val account = source.account
        val chains = source.chains
        val addresses = chains.associateWith { chain -> account.byChain.getValue(chain).address }
        val holdings = source.holdings.map { makeHolding(it, baseCurrencyRate) }
        val positionsProjection = makePositions(source)
        val fullyLoadedChains = source.fullyLoadedChains
        val portfolioWalletKeys = if (account.isMainnet) {
            addresses.map { (chain, address) -> "$chain:$address" }
        } else {
            emptyList()
        }

        val domainStates = JSONObject()
            .put("accounts", JSONObject().put("state", "fresh"))
            .put(
                "fungible",
                JSONObject().put(
                    "state",
                    if (source.hasBalances) "fresh" else "notLoaded"
                )
            )
            .put(
                "staking",
                JSONObject().put(
                    "state",
                    if ("ton" !in chains || positionsProjection.hasStakingData) {
                        "fresh"
                    } else {
                        "notLoaded"
                    }
                )
            )
            .put("vesting", JSONObject().put("state", "unavailable"))
            .put("vault", JSONObject().put("state", "unavailable"))
            .put("transactions", JSONObject().put("state", "stale"))
            .put(
                "value_series",
                JSONObject().put(
                    "state",
                    if (portfolioWalletKeys.isEmpty()) "unavailable" else "stale"
                )
            )
            .put("contacts", JSONObject().put("state", "fresh"))
        return JSONObject()
            .put("accountId", account.accountId)
            .put("label", normalizeAgentContextLabel(account.name, 80))
            .put("state", "active")
            .put(
                "accountType",
                when (account.accountType) {
                    MAccount.AccountType.VIEW -> "viewOnly"
                    MAccount.AccountType.HARDWARE -> "ledger"
                    MAccount.AccountType.MNEMONIC -> "regular"
                }
            )
            .put("isViewOnly", account.isViewOnly)
            .put("chains", JSONArray(chains))
            .put("addresses", JSONObject(addresses))
            .put("portfolioWalletKeys", JSONArray(portfolioWalletKeys))
            .put("holdings", JSONArray(holdings))
            .put(
                "positions",
                positionsProjection.positions.takeIf {
                    it.isNotEmpty() || positionsProjection.hasNftData ||
                        positionsProjection.hasStakingData
                }?.let(::JSONArray)
            )
            .put("savedAddresses", JSONArray(source.savedAddresses))
            .put("nftLoadedChains", JSONArray(chains.filter(fullyLoadedChains::contains)))
            .put("domainStates", domainStates)
    }

    private fun makeHolding(source: HoldingSource, baseCurrencyRate: Double?): JSONObject {
        val token = source.token
        val balance = atomicString(source.balance, token.decimals)
        val fiatPrice = token.priceUsd
            .takeIf { it.isFinite() && it >= 0 }
            ?.let { usdPrice ->
                baseCurrencyRate
                    ?.takeIf { it.isFinite() && it > 0 }
                    ?.let { usdPrice * it }
            }
        val fiatValue = fiatPrice?.let { price ->
            runCatching { BigDecimal(balance).multiply(BigDecimal.valueOf(price)).toPlainString() }
                .getOrNull()
        }
        return JSONObject()
            .put("asset", makeAsset(token))
            .put("balance", balance)
            .put("availableBalance", balance)
            .put("fiatValue", fiatValue)
            .put("fiatPrice", decimalString(fiatPrice))
            .put("valuationStatus", if (fiatValue == null) "unpriced" else "valued")
            .put("visibility", if (source.isHidden) "hidden" else "visible")
    }

    private fun makePositions(source: AccountSource): AgentV2PositionsProjection {
        val positions = buildList {
            source.nfts?.mapNotNullTo(this) { (nft, isHidden) -> makeNftPosition(nft, isHidden) }
            source.stakingStates?.mapNotNullTo(this, ::makeStakingPosition)
        }.sortedBy { it.getString("id") }
        return AgentV2PositionsProjection(
            positions = positions,
            hasNftData = source.nfts != null,
            hasStakingData = source.stakingStates != null
        )
    }

    private fun makeNftPosition(nft: ApiNft, isHidden: Boolean): JSONObject? {
        val chain = nft.chain?.name?.takeIf { it in MBlockchain.supportedChainValues }
            ?: return null
        return JSONObject()
            .put("id", "nft-${nft.address}")
            .put("kind", "nft")
            .put("chain", chain)
            .put("label", normalizeAgentContextLabel(nft.name ?: nft.collectionName ?: "NFT", 80))
            .put("valuationStatus", "not_applicable")
            .put("collection", nft.collectionName?.let { normalizeAgentContextLabel(it, 80) })
            .put("isOnSale", nft.isOnSale)
            .put("visibility", if (isHidden) "hidden" else "visible")
            .put("riskVerdict", if (nft.isScam == true) "spam" else null)
    }

    private fun makeStakingPosition(state: StakingState): JSONObject? {
        if (state.balance <= BigInteger.ZERO) return null
        val token = TokenStore.getToken(state.tokenSlug)
            ?.takeIf { it.chain in MBlockchain.supportedChainValues }
            ?: return null
        val rewards = (state as? StakingState.Jetton)
            ?.unclaimedRewards
            ?.takeIf { it > BigInteger.ZERO }
            ?.let { atomicString(it, token.decimals) }
        return JSONObject()
            .put("id", "staking-${state.id}")
            .put("kind", "staking")
            .put("chain", token.chain)
            .put("label", "${normalizeAgentContextLabel(token.symbol, 32)} staking")
            .put("asset", makeAsset(token))
            .put("quantity", atomicString(state.balance, token.decimals))
            .put("valuationStatus", "unpriced")
            .put(
                "status",
                if ((state.unstakeRequestAmount ?: BigInteger.ZERO) > BigInteger.ZERO) {
                    "unstaking"
                } else {
                    "active"
                }
            )
            .put("apy", decimalString(state.annualYield.toDouble()))
            .put("rewards", rewards)
            .put("visibility", "visible")
    }

    private fun makeSwapAsset(asset: MApiSwapAsset): JSONObject? {
        val chain = asset.chain?.takeIf { it in MBlockchain.supportedChainValues } ?: return null
        val symbol = asset.symbol?.takeIf { it.isNotBlank() } ?: return null
        if (asset.slug.isBlank() || asset.decimals < 0) return null
        return JSONObject()
            .put("slug", asset.slug)
            .put("chain", chain)
            .put("symbol", normalizeAgentContextLabel(symbol, 32))
            .put("name", asset.name?.let { normalizeAgentContextLabel(it, 80) })
            .put("tokenAddress", asset.tokenAddress)
            .put("decimals", asset.decimals)
            .put("priceUsd", decimalString(asset.priceUsd?.takeIf { it.isFinite() && it > 0 }))
    }

    private fun makeAsset(token: MToken) = JSONObject()
        .put("slug", token.slug)
        .put("chain", token.chain)
        .put("symbol", normalizeAgentContextLabel(token.symbol, 32))
        .put("name", normalizeAgentContextLabel(token.name, 80))
        .put("tokenAddress", token.tokenAddress)
        .put("decimals", token.decimals)
        .put("priceUsd", decimalString(token.priceUsd.takeIf { it.isFinite() && it >= 0 }))
        .put(
            "percentChange24h",
            decimalString(
                token.percentChange24hReal.takeIf {
                    it.isFinite()
                }
            )
        )

    private fun savedAddresses(accountId: String?): List<JSONObject> {
        val data =
            AddressStore.addressData?.takeIf { it.accountId == accountId } ?: return emptyList()
        return data.savedAddresses.orEmpty()
            .filter { it.chain in MBlockchain.supportedChainValues }
            .map { savedAddress ->
                JSONObject()
                    .put("id", savedAddressId(savedAddress.chain, savedAddress.address))
                    .put("name", normalizeAgentContextLabel(savedAddress.name, 80))
                    .put("chain", savedAddress.chain)
                    .put("address", savedAddress.address)
            }
    }

    private fun decimalString(value: Double?): String? = value
        ?.takeIf(Double::isFinite)
        ?.let(BigDecimal::valueOf)
        ?.stripTrailingZeros()
        ?.toPlainString()

    private fun atomicString(value: BigInteger, decimals: Int) =
        BigDecimal(value, decimals).stripTrailingZeros().toPlainString()

    // The most assets the SDK takes in a catalog, as web and iOS send
    private const val MAX_ASSET_CATALOG_SIZE = 10_000
}

private fun savedAddressId(chain: String, address: String) = "$chain:$address"

private val contextWhitespacePattern = Regex("\\s+")

internal fun normalizeAgentContextLabel(value: String, limit: Int): String {
    val requiresNormalization = value.indices.any { index ->
        val char = value[index]
        char !in ' '..'~' || (
            char == ' ' &&
                (index == 0 || index == value.lastIndex || value[index - 1] == ' ')
            )
    }
    if (!requiresNormalization) return value.take(limit)
    return value.filterNot(Char::isISOControl)
        .trim()
        .split(contextWhitespacePattern)
        .joinToString(" ")
        .take(limit)
}
