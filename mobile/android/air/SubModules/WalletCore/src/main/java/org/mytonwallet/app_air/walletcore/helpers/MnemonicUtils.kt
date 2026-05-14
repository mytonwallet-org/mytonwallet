package org.mytonwallet.app_air.walletcore.helpers

fun String.toMnemonicRegex(): Regex {
    return map { Regex.escape(it.toString()) }
        .joinToString(".*", prefix = "^", postfix = ".*$")
        .toRegex()
}

fun Array<String>.findMnemonicMatches(query: String): List<String> {
    if (query.isEmpty()) {
        return emptyList()
    }

    val regex = query.toMnemonicRegex()
    // non-regex match has higher priority
    val (prefixMatches, otherWords) = partition { it.startsWith(query) }
    return prefixMatches + otherWords.filter(regex::matches)
}
