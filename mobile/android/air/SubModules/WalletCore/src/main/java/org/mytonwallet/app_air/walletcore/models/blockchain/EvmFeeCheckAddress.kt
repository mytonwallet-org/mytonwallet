package org.mytonwallet.app_air.walletcore.models.blockchain

/**
 * Low 20 bytes of `sha3_256("mytonwallet fee-check address")`. Must hold nothing: OpenZeppelin
 * ERC20s revert on the zero address, and a funded recipient under-reports the gas of a fresh one.
 */
const val EVM_FEE_CHECK_ADDRESS = "0x93fa28647b06ab40554d6905e4e9d8e8bb24380c"
