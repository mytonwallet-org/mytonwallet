package org.mytonwallet.app_air.walletcontext.utils

private val evmNftContract = Regex("^0x[\\da-f]{40}(?=/)", RegexOption.IGNORE_CASE)

// Keep persisted preference keys compatible with the SDK's canonical EVM NFT addresses.
fun normalizeNftAddress(address: String): String =
    evmNftContract.replace(address) { it.value.lowercase() }
