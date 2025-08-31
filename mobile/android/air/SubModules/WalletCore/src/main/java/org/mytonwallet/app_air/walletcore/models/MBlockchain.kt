package org.mytonwallet.app_air.walletcore.models

import android.graphics.Color
import com.squareup.moshi.JsonClass
import org.mytonwallet.app_air.icons.R
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.helpers.ExplorerHelpers
import java.math.BigDecimal

@JsonClass(generateAdapter = false)
enum class MBlockchain(
    val icon: Int,
    val nativeSlug: String
) {
    ton(R.drawable.ic_blockchain_ton_128, "toncoin"),
    ethereum(R.drawable.ic_blockchain_ethereum_128, "eth"),
    polkadot(R.drawable.ic_blockchain_polkadot_128, "dot"),
    zcash(R.drawable.ic_blockchain_zcash_128, "zec"),
    internet_computer(R.drawable.ic_blockchain_internet_computer_40, "icp"),
    avalanche(R.drawable.ic_blockchain_avalanche_128, "avax"),
    litecoin(R.drawable.ic_blockchain_litecoin_128, "ltc"),
    cosmos(R.drawable.ic_blockchain_cosmos_128, "atom"),
    ripple(R.drawable.ic_blockchain_ripple_128, "xrp"),
    ethereum_classic(R.drawable.ic_blockchain_ethereum_classic_128, "etc"),
    binance_smart_chain(R.drawable.ic_blockchain_bnb_128, "bsc"),
    dash(R.drawable.ic_blockchain_dash_128, "dash"),
    monero(R.drawable.ic_blockchain_monero_128, "xmr"),
    tron(R.drawable.ic_blockchain_tron_40, "trx"),
    cardano(R.drawable.ic_blockchain_cardano_128, "ada"),
    bitcoin(R.drawable.ic_blockchain_bitcoin_40, "btc"),
    eos(R.drawable.ic_blockchain_eos_128, "eos"),
    bitcoin_cash(R.drawable.ic_blockchain_bitcoin_cash_128, "bch"),
    solana(R.drawable.ic_blockchain_solana_40, "sol"),
    doge(R.drawable.ic_blockchain_doge_128, "doge"),
    stellar(R.drawable.ic_blockchain_stellar_128, "xlm"),
    binance_dex(R.drawable.ic_blockchain_bnb_128, "bnb");

    data class Gas(
        val maxSwap: BigDecimal?,
        val maxTransfer: BigDecimal,
        val maxTransferToken: BigDecimal
    )

    val gas: Gas?
        get() = when (this) {
            ton -> Gas(
                maxSwap = BigDecimal("0.4"),
                maxTransfer = BigDecimal("0.015"),
                maxTransferToken = BigDecimal("0.06")
            )

            tron -> Gas(
                maxSwap = null,
                maxTransfer = BigDecimal("1"),
                maxTransferToken = BigDecimal("30")
            )

            else -> null
        }


    val symbolIcon: Int?
        get() {
            return when (this) {
                ton ->
                    return R.drawable.ic_symbol_ton

                tron ->
                    return R.drawable.ic_symbol_tron

                else ->
                    null
            }
        }

    val gradientColors: IntArray?
        get() {
            return when (this) {
                ton ->
                    return intArrayOf(
                        Color.parseColor("#2C95A9"),
                        Color.parseColor("#2A5BA5")
                    )

                tron ->
                    return intArrayOf(
                        Color.parseColor("#AC4338"),
                        Color.parseColor("#A42F5C")
                    )

                else ->
                    null
            }
        }

    val isCommentSupported: Boolean
        get() {
            return this == ton
        }

    fun explorerUrl(address: String): String {
        val str: String
        when (this) {
            ton -> {
                val domain = ExplorerHelpers.tonScanUrl(WalletCore.activeNetwork)
                str = "${domain}address/$address"
            }

            tron -> {
                val domain = ExplorerHelpers.tronScanUrl(WalletCore.activeNetwork)
                str = "${domain}address/$address"
            }

            else -> {
                str = ""
            }
        }
        return str
    }

    fun isValidAddress(address: String): Boolean {
        return when (this) {
            ton -> Regex("""^([-\w_]{48}|0:[\da-fA-F]{64})$""").matches(address)
            tron -> Regex("""^T[1-9A-HJ-NP-Za-km-z]{33}$""").matches(address)

            else -> false
        }
    }

    companion object {
        val supportedChains = listOf(ton, tron)
        val supportedChainValues = listOf("ton", "tron")

        fun isValidAddressOnAnyChain(address: String): Boolean {
            return supportedChains.any {
                it.isValidAddress(address)
            }
        }
    }
}
