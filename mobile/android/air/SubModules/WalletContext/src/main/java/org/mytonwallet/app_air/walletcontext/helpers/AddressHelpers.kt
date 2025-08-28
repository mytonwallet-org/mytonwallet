package org.mytonwallet.app_air.walletcontext.helpers

import java.net.URLEncoder
import java.nio.charset.StandardCharsets

class AddressHelpers {
    companion object {

        private fun urlEncodedStringFromString(input: String): String {
            return URLEncoder.encode(input, StandardCharsets.UTF_8.toString())
        }

        fun walletInvoiceUrl(
            address: String,
            comment: String? = null,
            jetton: String? = null,
            amount: String? = null
        ): String {
            var arguments = ""

            if (!comment.isNullOrEmpty()) {
                arguments += if (arguments.isEmpty()) "?" else "&"
                arguments += "text=${urlEncodedStringFromString(comment)}"
            }

            if (!jetton.isNullOrEmpty()) {
                arguments += if (arguments.isEmpty()) "?" else "&"
                arguments += "jetton=$jetton"
            }

            if (!amount.isNullOrEmpty()) {
                arguments += if (arguments.isEmpty()) "?" else "&"
                arguments += "amount=$amount"
            }

            return "ton://transfer/$address$arguments"
        }

        private val invalidAddressCharacters = "[^A-Za-z0-9_=-]".toRegex()
        fun isValidAddress(address: String, exactLength: Boolean = true): Boolean {
            val walletAddressLength = 48

            if (address.length > walletAddressLength || invalidAddressCharacters.containsMatchIn(
                    address
                )
            ) {
                return false
            }
            if (exactLength && address.length != walletAddressLength) {
                return false
            }
            return true
        }

        fun isFriendly(source: String): Boolean {
            if (source.length != 48) {
                return false
            }
            if (!Regex("[A-Za-z0-9+/_-]+").matches(source)) {
                return false
            }
            return true
        }

        fun isFriendlyAddressBounceable(friendlyAddress: String): Boolean {
            return friendlyAddress.startsWith("E")
        }
    }
}
