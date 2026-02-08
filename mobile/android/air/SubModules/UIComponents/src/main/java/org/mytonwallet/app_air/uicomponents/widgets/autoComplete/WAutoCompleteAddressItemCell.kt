package org.mytonwallet.app_air.uicomponents.widgets.autoComplete

import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.models.MSavedAddress

interface IAutoCompleteAddressItemCell {

    fun configure(
        item: AutoCompleteAddressItem,
        isLast: Boolean,
        onTap: () -> Unit,
        onLongClick: (() -> Unit)?
    )
}

data class AutoCompleteAddressItem(
    val identifier: Identifier,
    val title: String,
    val network: MBlockchainNetwork,
    val account: MAccount? = null,
    val savedAddress: MSavedAddress? = null,
    val value: String? = null,
    val keyword: String = ""
) {

    enum class Identifier {
        ACCOUNT,
        HEADER
    }
}

data class AutoCompleteAddressSection(
    val section: Section,
    var children: List<AutoCompleteAddressItem>
) {
    enum class Section {
        SAVED,
        ADDED
    }
}
