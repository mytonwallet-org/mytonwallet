package org.mytonwallet.app_air.uiassets.viewControllers.token.helpers

class DatasetHelpers {
    companion object {
        fun getHistoryDataInRange(
            historyData: Array<Array<Double>>?,
            startPercentage: Float,
            endPercentage: Float
        ): Array<Array<Double>>? {
            val data = historyData ?: return null
            if (data.isEmpty()) return emptyArray()

            val dataSize = data.size
            val startIndex = (startPercentage * dataSize).toInt().coerceIn(0, dataSize - 1)
            val endIndex = (endPercentage * dataSize).toInt().coerceIn(0, dataSize - 1)

            return if (startIndex < endIndex) {
                data.slice(startIndex..endIndex).toTypedArray()
            } else {
                emptyArray()
            }
        }
    }
}
