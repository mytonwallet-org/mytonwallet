package org.mytonwallet.app_air.uitonconnect.viewControllers

import org.mytonwallet.app_air.walletcore.moshi.MSignDataPayload

internal enum class SignDataWarningKind {
    GENERIC_TRUST
}

internal fun signDataWarningKinds(payload: MSignDataPayload): List<SignDataWarningKind> =
    listOf(SignDataWarningKind.GENERIC_TRUST)

internal val SignDataWarningKind.localizationKey: String
    get() = when (this) {
        SignDataWarningKind.GENERIC_TRUST -> "\$signature_warning"
    }
