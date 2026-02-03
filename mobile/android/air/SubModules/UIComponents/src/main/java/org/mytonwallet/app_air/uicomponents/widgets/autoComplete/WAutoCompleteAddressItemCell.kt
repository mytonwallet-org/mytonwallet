package org.mytonwallet.app_air.uicomponents.widgets.autoComplete

import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.models.MSavedAddress

interface IAutoCompleteAddressItemCell {

    fun configure(
        item: AutoCompleteAddressItem,
        onTap: () -> Unit,
        changeAnimationFinishListener: (() -> Unit),
        onLongClick: (() -> Unit)?
    )

    fun hasActiveAnimation(): Boolean
}

data class AutoCompleteAddressItem(
    val listId: String,
    val title: String,
    val network: MBlockchainNetwork,
    val account: MAccount? = null,
    val savedAddress: MSavedAddress? = null,
    val value: String? = null,
    val keyword: String = "",
    val isFirst: Boolean = false,
    val isLast: Boolean = false,
    val animationState: AnimationState = AnimationState.IDLE
) {
    enum class AnimationState {
        IDLE, DISAPPEARING, CORNER_ROUNDING
    }
}

data class AutoCompleteAddressSection(
    val section: Section,
    val children: List<AutoCompleteAddressItem>
) {
    enum class Section {
        SAVED,
        ADDED
    }
}
