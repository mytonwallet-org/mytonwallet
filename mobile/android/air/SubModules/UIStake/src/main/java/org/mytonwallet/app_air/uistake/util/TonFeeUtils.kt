package org.mytonwallet.app_air.uistake.util

import java.math.BigInteger

data class TonOperationFees(
    val gas: BigInteger,
    val real: BigInteger
)

const val DEFAULT_FEE = 15_000_000L
const val ONE_TON = 1_000_000_000L
const val TOKEN_TRANSFER_AMOUNT = 50_000_000L

enum class TonGasOperation {
    STAKE_NOMINATORS,
    UNSTAKE_NOMINATORS,
    STAKE_LIQUID,
    UNSTAKE_LIQUID,
    STAKE_JETTONS,
    UNSTAKE_JETTONS,
    CLAIM_JETTONS,
    STAKE_ETHENA,
    UNSTAKE_ETHENA,
    UNSTAKE_ETHENA_LOCKED,
}

val TON_GAS = mapOf(
    TonGasOperation.STAKE_NOMINATORS to ONE_TON,
    TonGasOperation.UNSTAKE_NOMINATORS to ONE_TON,
    TonGasOperation.STAKE_LIQUID to ONE_TON,
    TonGasOperation.UNSTAKE_LIQUID to ONE_TON,
    TonGasOperation.STAKE_JETTONS to JettonStakingGas.STAKE_JETTONS + TOKEN_TRANSFER_AMOUNT,
    TonGasOperation.UNSTAKE_JETTONS to JettonStakingGas.UNSTAKE_JETTONS,
    TonGasOperation.CLAIM_JETTONS to JettonStakingGas.JETTON_TRANSFER + JettonStakingGas.SIMPLE_UPDATE_REQUEST,
    TonGasOperation.STAKE_ETHENA to TOKEN_TRANSFER_AMOUNT + 100_000_000L,
    TonGasOperation.UNSTAKE_ETHENA to TOKEN_TRANSFER_AMOUNT + 100_000_000L,
    TonGasOperation.UNSTAKE_ETHENA_LOCKED to 150_000_000L,
)

val TON_GAS_REAL = mapOf(
    TonGasOperation.STAKE_NOMINATORS to 1_000_052_853L,
    TonGasOperation.UNSTAKE_NOMINATORS to 148_337_433L,
    TonGasOperation.STAKE_LIQUID to 20_251_387L,
    TonGasOperation.UNSTAKE_LIQUID to 18_625_604L,
    TonGasOperation.STAKE_JETTONS to 74_879_996L,
    TonGasOperation.UNSTAKE_JETTONS to 59_971_662L,
    TonGasOperation.CLAIM_JETTONS to 57_053_859L,
    TonGasOperation.STAKE_ETHENA to 116_690_790L,
    TonGasOperation.UNSTAKE_ETHENA to 113_210_330L,
    TonGasOperation.UNSTAKE_ETHENA_LOCKED to 37_612_000L,
)

object JettonStakingGas {
    const val STAKE_JETTONS = 300_000_000L
    const val UNSTAKE_JETTONS = 340_000_000L
    const val JETTON_TRANSFER = 55_000_000L
    const val SIMPLE_UPDATE_REQUEST = 340_000_000L
}

fun getTonOperationFees(operation: TonGasOperation): TonOperationFees {
    return TonOperationFees(
        gas = ((TON_GAS[operation] ?: 0L) + DEFAULT_FEE).toBigInteger(),
        real = (TON_GAS_REAL[operation] ?: 0L).toBigInteger()
    )
}

fun getTonStakingFees(type: String?): Map<String, TonOperationFees> {
    return when (type) {
        "nominators" -> mapOf(
            "stake" to getTonOperationFees(TonGasOperation.STAKE_NOMINATORS),
            "unstake" to getTonOperationFees(TonGasOperation.UNSTAKE_NOMINATORS)
        )

        "liquid" -> mapOf(
            "stake" to getTonOperationFees(TonGasOperation.STAKE_LIQUID),
            "unstake" to getTonOperationFees(TonGasOperation.UNSTAKE_LIQUID)
        )

        "jetton" -> mapOf(
            "stake" to getTonOperationFees(TonGasOperation.STAKE_JETTONS),
            "unstake" to getTonOperationFees(TonGasOperation.UNSTAKE_JETTONS),
            "claim" to getTonOperationFees(TonGasOperation.CLAIM_JETTONS)
        )

        "ethena" -> mapOf(
            "stake" to getTonOperationFees(TonGasOperation.STAKE_ETHENA),
            "unstake" to getTonOperationFees(TonGasOperation.UNSTAKE_ETHENA),
            "claim" to getTonOperationFees(TonGasOperation.UNSTAKE_ETHENA_LOCKED),
        )

        else -> mapOf(
            "stake" to TonOperationFees(BigInteger.ZERO, BigInteger.ZERO),
            "unstake" to TonOperationFees(BigInteger.ZERO, BigInteger.ZERO)
        )
    }
}
