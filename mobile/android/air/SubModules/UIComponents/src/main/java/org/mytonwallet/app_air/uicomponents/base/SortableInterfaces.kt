package org.mytonwallet.app_air.uicomponents.base

interface ISortableView {
    fun startSorting()
    fun endSorting()
}

interface ISortableController {
    fun startSorting()
    fun endSorting(save: Boolean)
}
