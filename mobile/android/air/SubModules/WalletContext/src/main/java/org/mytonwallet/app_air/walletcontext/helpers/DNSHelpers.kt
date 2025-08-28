package org.mytonwallet.app_air.walletcontext.helpers

class DNSHelpers {

    data class DnsZone(
        val suffixes: List<String>,
        val baseFormat: Regex,
        val resolver: String,
        val collectionName: String,
        val isTelemint: Boolean = false,
        val isUnofficial: Boolean = false
    )

    data class DnsMatch(val base: String, val zone: DnsZone)

    companion object {
        private val TON_DNS_ZONES = listOf(
            DnsZone(
                suffixes = listOf("ton"),
                baseFormat = Regex(
                    "^([\\-\\da-z]+\\.){0,2}[\\-\\da-z]{4,126}$",
                    RegexOption.IGNORE_CASE
                ),
                resolver = "EQC3dNlesgVD8YbAazcauIrXBPfiVhMMr5YYk2in0Mtsz0Bz",
                collectionName = "TON DNS Domains"
            ),
            DnsZone(
                suffixes = listOf("t.me"),
                baseFormat = Regex(
                    "^([\\-\\da-z]+\\.){0,2}[-_\\da-z]{4,32}$",
                    RegexOption.IGNORE_CASE
                ),
                resolver = "EQCA14o1-VWhS2efqoh_9M1b_A9DtKTuoqfmkn83AbJzwnPi",
                isTelemint = true,
                collectionName = "Telegram Usernames"
            ),
            DnsZone(
                suffixes = listOf("vip", "ton.vip", "vip.ton"),
                baseFormat = Regex(
                    "^([\\-\\da-z]+\\.){0,2}?[\\da-z]{1,24}$",
                    RegexOption.IGNORE_CASE
                ),
                resolver = "EQBWG4EBbPDv4Xj7xlPwzxd7hSyHMzwwLB5O6rY-0BBeaixS",
                collectionName = "VIP DNS Domains",
                isUnofficial = true
            ),
            DnsZone(
                suffixes = listOf("gram"),
                baseFormat = Regex(
                    "^([\\-\\da-z]+\\.){0,2}[\\da-z]{1,127}$",
                    RegexOption.IGNORE_CASE
                ),
                resolver = "EQAic3zPce496ukFDhbco28FVsKKl2WUX_iJwaL87CBxSiLQ",
                collectionName = "GRAM DNS Domains",
                isUnofficial = true
            )
        )

        private fun getDnsDomainZone(domain: String): DnsMatch? {
            for (zone in TON_DNS_ZONES) {
                val suffixes = zone.suffixes
                for (i in suffixes.indices.reversed()) {
                    val suffix = suffixes[i]
                    if (!domain.endsWith(".$suffix")) continue

                    val base = domain.dropLast(suffix.length + 1)
                    if (!zone.baseFormat.matches(base)) continue

                    return DnsMatch(base, zone)
                }
            }
            return null
        }

        fun isDnsDomain(value: String): Boolean {
            return getDnsDomainZone(value) != null
        }
    }
}
