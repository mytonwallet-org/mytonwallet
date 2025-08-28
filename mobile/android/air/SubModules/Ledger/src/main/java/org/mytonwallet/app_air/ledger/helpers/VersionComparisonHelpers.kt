package org.mytonwallet.app_air.ledger.helpers

class VersionComparisonHelpers {
    companion object {
        fun compareVersions(versionA: String, versionB: String): Int {
            val partsA = versionA.split(".").map { it.toInt() }
            val partsB = versionB.split(".").map { it.toInt() }

            for (i in 0 until maxOf(partsA.size, partsB.size)) {
                val partA = partsA.getOrNull(i) ?: 0
                val partB = partsB.getOrNull(i) ?: 0

                if (partA > partB) return 1
                if (partA < partB) return -1
            }

            return 0
        }
    }
}
