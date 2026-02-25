package org.mytonwallet.app_air.walletcore.helpers

object PrivateKeyHelper {
    private const val PRIVATE_KEY_HEX_LENGTH = 64
    private const val PRIVATE_KEY_WITH_PUBLIC_KEY_HEX_LENGTH = 128

    fun isValidPrivateKeyHex(privateKey: String): Boolean {
        return privateKey.length == PRIVATE_KEY_HEX_LENGTH || privateKey.length == PRIVATE_KEY_WITH_PUBLIC_KEY_HEX_LENGTH
    }

    fun normalizePrivateKeyHex(privateKey: String): String? {
        if (!isValidPrivateKeyHex(privateKey)) return null
        return if (privateKey.length == PRIVATE_KEY_HEX_LENGTH) privateKey
        else privateKey.take(PRIVATE_KEY_HEX_LENGTH)
    }

    fun normalizeMnemonicPrivateKey(mnemonic: Array<String>): Array<String>? {
        if (mnemonic.size != 1) return null
        val privateKey = normalizePrivateKeyHex(mnemonic[0]) ?: return null
        return arrayOf(privateKey)
    }

    fun isMnemonicPrivateKey(mnemonic: Array<String>): Boolean {
        return normalizeMnemonicPrivateKey(mnemonic) != null
    }
}
