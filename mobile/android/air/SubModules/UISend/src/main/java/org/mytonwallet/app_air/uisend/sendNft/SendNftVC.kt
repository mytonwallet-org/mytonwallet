package org.mytonwallet.app_air.uisend.sendNft

import android.animation.Animator
import android.annotation.SuppressLint
import android.content.Context
import android.os.Build
import android.text.Editable
import android.text.TextWatcher
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.Space
import org.mytonwallet.app_air.uicomponents.widgets.WEditText
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.constraintlayout.widget.ConstraintLayout.LayoutParams.MATCH_CONSTRAINT
import androidx.core.view.isGone
import androidx.core.view.isVisible
import androidx.core.view.updateLayoutParams
import androidx.core.widget.doOnTextChanged
import com.google.android.material.chip.ChipGroup
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.adapter.implementation.holders.ListIconDualLineCell
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.commonViews.AddressInputLayout
import org.mytonwallet.app_air.uicomponents.commonViews.ReversedCornerViewUpsideDown
import org.mytonwallet.app_air.uicomponents.commonViews.cells.HeaderCell
import org.mytonwallet.app_air.uicomponents.extensions.animatorSet
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.uicomponents.widgets.WButton
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WScrollView
import org.mytonwallet.app_air.uicomponents.widgets.WTagView
import org.mytonwallet.app_air.uicomponents.widgets.autoComplete.WAutoCompleteAddressView
import org.mytonwallet.app_air.uicomponents.widgets.hideKeyboard
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uicomponents.widgets.setRoundedOutline
import org.mytonwallet.app_air.uisend.sendNft.sendNftConfirm.ConfirmNftVC
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.smartDecimalsCount
import org.mytonwallet.app_air.walletbasecontext.utils.toString
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.helpers.WInterpolator
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.models.MBridgeError
import org.mytonwallet.app_air.walletcore.models.MSavedAddress
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.ApiNft
import org.mytonwallet.app_air.walletcore.moshi.MApiTransaction
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore
import java.lang.ref.WeakReference
import java.math.BigInteger
import kotlin.math.max

@SuppressLint("ViewConstructor")
class SendNftVC(
    context: Context,
    val nfts: List<ApiNft>,
) : WViewController(context), SendNftVM.Delegate, WalletCore.EventObserver {

    private companion object {
        const val MAX_VISIBLE_NFT_TAGS = 10
    }

    constructor(context: Context, nft: ApiNft) : this(context, listOf(nft))

    override val TAG = "SendNft"

    override val displayedAccount =
        DisplayedAccount(AccountStore.activeAccountId, AccountStore.isPushedTemporary)

    private val viewModel = SendNftVM(this, nfts)
    private val firstNft = nfts.first()
    private val chain = firstNft.chain ?: MBlockchain.ton
    private var suggestionAnimator: Animator? = null

    private val title1 = HeaderCell(context).apply {
        id = View.generateViewId()
        configure(
            LocaleController.getString("Send to"),
            titleColor = WColor.Tint,
            topRounding = HeaderCell.TopRounding.FIRST_ITEM
        )
    }

    private val addressInputView by lazy {
        AddressInputLayout(
            viewController = WeakReference(this),
            autoCompleteConfig = AddressInputLayout.AutoCompleteConfig(
                type = AddressInputLayout.AutoCompleteConfig.Type.EXTERNAL
            ),
            onTextEntered = { keyword ->
                hideSuggestions()
                clearAddressFocus()
                val addressInfo = viewModel.addressInfo
                if (addressInfo?.input == keyword) {
                    updateAddressOverlay(addressInfo, keyword)
                } else {
                    viewModel.onDestinationEntered(keyword)
                }
                suggestionsBoxView.search(keyword, true)
            }).apply {
            id = View.generateViewId()
            showCloseOnTextEditing = true
            activeChain = chain
            pasteInterceptor = { pastedText ->
                val address = pastedText.trim()
                if (!MBlockchain.isValidAddressOnAnyChain(address)) {
                    false
                } else {
                    hideSuggestions()
                    clearAddressFocus()
                    viewModel.onInputDestination(address)
                    viewModel.onDestinationEntered(address)
                    true
                }
            }
            focusCallback = { hasFocus ->
                if (hasFocus) {
                    showSuggestions()
                    suggestionsBoxView.search(getKeyword())
                }
            }
            addTextChangedListener { input ->
                suggestionsBoxView.search(input)
            }
            textFieldTopPadding = 12.dp
            textFieldBottomPadding = 14.dp
        }
    }

    private val suggestionsBoxView: WAutoCompleteAddressView by lazy {
        WAutoCompleteAddressView(context).apply {
            autoCompleteConfig = AddressInputLayout.AutoCompleteConfig(
                type = AddressInputLayout.AutoCompleteConfig.Type.EXTERNAL
            )
            activeChain = chain
            search("")
            isGone = true
            setRoundedOutline(ViewConstants.BLOCK_RADIUS.dp)
            onSelected = { account, savedAddress ->
                val activeChainName = addressInputView.activeChain.name
                when {
                    account != null && account.addressByChain.containsKey(activeChainName) -> {
                        addressInputView.setAccount(account)
                        hideSuggestions()
                        clearAddressFocus()
                        viewModel.onDestinationEntered(addressInputView.getKeyword())
                    }

                    savedAddress != null && savedAddress.chain == activeChainName -> {
                        addressInputView.setAddress(savedAddress)
                        hideSuggestions()
                        clearAddressFocus()
                        viewModel.onDestinationEntered(addressInputView.getKeyword())
                    }

                    else -> suggestionsBoxView.search(addressInputView.getKeyword())
                }
            }
            viewController = WeakReference(this@SendNftVC)
        }
    }

    private val title2 = HeaderCell(context).apply {
        id = View.generateViewId()
        configure(
            LocaleController.getString("Asset"),
            titleColor = WColor.Tint,
            topRounding = HeaderCell.TopRounding.NORMAL
        )
    }

    private val nftView by lazy {
        ListIconDualLineCell(context).apply {
            id = View.generateViewId()
            configure(
                Content.ofUrl(firstNft.image ?: ""),
                firstNft.name,
                firstNft.collectionName,
                false,
                12f.dp
            )
        }
    }

    private val multipleNftView by lazy {
        ChipGroup(context).apply {
            id = View.generateViewId()
            setPaddingDp(16)
            isSingleLine = false
            chipSpacingHorizontal = 8.dp
            chipSpacingVertical = 8.dp
            nfts.take(MAX_VISIBLE_NFT_TAGS).forEach { nft ->
                addView(WTagView(context).apply {
                    configure(Content.ofUrl(nft.thumbnail ?: nft.image ?: ""), nft.name)
                })
            }
            val remainingNfts = nfts.size - MAX_VISIBLE_NFT_TAGS
            if (remainingNfts > 0) {
                addView(
                    WLabel(context).apply {
                        setStyle(14f, WFont.Regular)
                        setTextColor(WColor.SecondaryText)
                        gravity = Gravity.CENTER_VERTICAL
                        text = LocaleController.getString("%amount% NFTs")
                            .replace("%amount%", "+$remainingNfts")
                    },
                    ViewGroup.LayoutParams(WRAP_CONTENT, 28.dp)
                )
            }
        }
    }

    private val title3 = HeaderCell(context).apply {
        id = View.generateViewId()
        configure(
            LocaleController.getString("Comment or Memo"),
            titleColor = WColor.Tint,
            topRounding = HeaderCell.TopRounding.NORMAL
        )
    }

    private val assetContentView by lazy {
        LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            if (nfts.size == 1) {
                addView(title2, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
                addView(
                    nftView,
                    ViewGroup.LayoutParams(MATCH_PARENT, ListIconDualLineCell.HEIGHT.dp)
                )
            } else {
                addView(
                    multipleNftView,
                    ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT)
                )
            }
        }
    }

    private val commentInputView by lazy {
        WEditText(context, multilinePaste = false).apply {
            hint = LocaleController.getString("Add a message, if needed")
            setStyle(16f)
            layoutParams =
                ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT)
            setPaddingDp(20, 13, 20, 20)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                setLineHeight(TypedValue.COMPLEX_UNIT_SP, 24f)
            }
        }
    }

    private val feeLabel by lazy {
        WLabel(context).apply {
            id = View.generateViewId()
            setStyle(14f)
            setLineHeight(20f)
            gravity = Gravity.CENTER_HORIZONTAL
            textAlignment = View.TEXT_ALIGNMENT_CENTER
            setPaddingDp(0, 0, 0, 0)
            visibility = View.GONE
        }
    }

    private val headerContentContainer by lazy {
        LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            if (nfts.size > 1) {
                addView(assetContentView, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
                addView(Space(context), ViewGroup.LayoutParams(MATCH_PARENT, ViewConstants.GAP.dp))
            }
            addView(title1, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
            addView(addressInputView, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
            addView(Space(context), ViewGroup.LayoutParams(MATCH_PARENT, ViewConstants.GAP.dp))
        }
    }

    private val primaryContent by lazy {
        LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            if (nfts.size == 1) {
                addView(assetContentView, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
                addView(Space(context), ViewGroup.LayoutParams(MATCH_PARENT, ViewConstants.GAP.dp))
            }
            addView(title3, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
            addView(commentInputView, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        }
    }

    private val dynamicContentContainer by lazy {
        FrameLayout(context).apply {
            clipChildren = false
            addView(primaryContent, FrameLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
            addView(suggestionsBoxView, FrameLayout.LayoutParams(MATCH_PARENT, 0))
        }
    }

    private val linearLayout by lazy {
        LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            clipChildren = false
            setPadding(
                ViewConstants.HORIZONTAL_PADDINGS.dp,
                0,
                ViewConstants.HORIZONTAL_PADDINGS.dp,
                0
            )
            addView(headerContentContainer, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
            addView(dynamicContentContainer, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        }
    }

    private val scrollView by lazy {
        WScrollView(WeakReference(this)).apply {
            addView(
                linearLayout,
                ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT)
            )
            id = View.generateViewId()
        }
    }

    private val bottomReversedCornerViewUpsideDown: ReversedCornerViewUpsideDown =
        ReversedCornerViewUpsideDown(context, scrollView).apply {
            if (ignoreSideGuttering)
                setHorizontalPadding(0f)
        }

    private val continueButton by lazy {
        WButton(context).apply {
            id = View.generateViewId()
        }.apply {
            isEnabled = false
            text = LocaleController.getString("Address or Domain")
        }
    }

    private val onInputDestinationTextWatcher = object : TextWatcher {
        override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
        override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {
            val destination = viewModel.inputAddress.trim()
            val address = s?.toString() ?: ""
            if (destination == address) return
            viewModel.onInputDestination(address)
            if (address.isBlank()) {
                viewModel.onDestinationEntered("")
                updateContinueButtonType(false)
            }
        }

        override fun afterTextChanged(s: Editable?) {}
    }

    override fun setupViews() {
        super.setupViews()

        WalletCore.registerObserver(this)
        setNavTitle(
            LocaleController.getString(
                if (nfts.size > 1) "Send Collectibles" else "Send Collectible"
            )
        )
        setupNavBar(true)

        view.addView(scrollView, ViewGroup.LayoutParams(MATCH_PARENT, 0))
        view.addView(
            bottomReversedCornerViewUpsideDown,
            ConstraintLayout.LayoutParams(
                MATCH_PARENT,
                MATCH_CONSTRAINT
            )
        )
        scrollView.addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ ->
            val suggestionsBoxHeight =
                (scrollView.height - linearLayout.paddingBottom) - headerContentContainer.height
            val safeHeight = max(0, suggestionsBoxHeight)
            if (suggestionsBoxView.layoutParams.height != safeHeight) {
                suggestionsBoxView.updateLayoutParams { height = safeHeight }
            }
        }
        view.addView(
            feeLabel,
            ViewGroup.LayoutParams(WRAP_CONTENT, WRAP_CONTENT)
        )
        view.addView(continueButton, ViewGroup.LayoutParams(MATCH_PARENT, 50.dp))
        view.setConstraints {
            toCenterX(scrollView)
            topToBottom(scrollView, navigationBar!!)
            bottomToTop(scrollView, feeLabel, 12f)
            toCenterX(feeLabel)
            bottomToTop(feeLabel, continueButton, 16f)
            topToTop(
                bottomReversedCornerViewUpsideDown,
                continueButton,
                -ViewConstants.GAP - ViewConstants.BLOCK_RADIUS
            )
            toBottom(bottomReversedCornerViewUpsideDown)
            toCenterX(continueButton, 20f)
            toBottomPx(
                continueButton, 20.dp + max(
                    (navigationController?.getSystemBars()?.bottom ?: 0),
                    (window?.imeInsets?.bottom ?: 0)
                )
            )
        }

        continueButton.setOnClickListener {
            val resolvedAddress = viewModel.resolvedAddress ?: return@setOnClickListener
            val feeValue = viewModel.feeValue ?: return@setOnClickListener
            val confirmNftVC = ConfirmNftVC(
                context,
                ConfirmNftVC.Mode.Send(
                    chain,
                    viewModel.inputAddress,
                    resolvedAddress,
                    feeValue,
                    addressName = addressInputView.autocompleteResult?.name
                        ?: viewModel.addressName,
                    isScam = viewModel.isScam || viewModel.addressInfo?.isScam == true
                ),
                nfts,
                viewModel.inputComment
            )
            view.hideKeyboard()
            push(confirmNftVC)
        }

        addressInputView.addTextChangedListener(onInputDestinationTextWatcher)
        addressInputView.doAfterQrCodeScanned { address ->
            viewModel.onDestinationEntered(address)
        }

        commentInputView.doOnTextChanged { text, _, _, _ ->
            viewModel.onInputComment(text.toString())
        }
        updateTheme()
    }

    override fun onDestroy() {
        super.onDestroy()
        suggestionAnimator?.cancel()
        viewModel.onDestroy()
        WalletCore.unregisterObserver(this)
        addressInputView.removeTextChangedListener(onInputDestinationTextWatcher)
    }

    override fun updateTheme() {
        super.updateTheme()
        view.setBackgroundColor(WColor.SecondaryBackground.color)
        addressInputView.setBackgroundColor(
            WColor.Background.color,
            0f,
            ViewConstants.BLOCK_RADIUS.dp
        )
        nftView.setBackgroundColor(
            WColor.Background.color,
            0f,
            ViewConstants.BLOCK_RADIUS.dp
        )
        multipleNftView.setBackgroundColor(
            WColor.Background.color, ViewConstants.BLOCK_RADIUS.dp
        )
        commentInputView.setBackgroundColor(
            WColor.Background.color,
            0f,
            ViewConstants.BLOCK_RADIUS.dp
        )
        commentInputView.setTextColor(WColor.PrimaryText.color)
        commentInputView.setHintTextColor(WColor.SecondaryText.color)
        feeLabel.setTextColor(WColor.SecondaryText)
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        view.setConstraints {
            toBottomPx(
                continueButton, 20.dp + max(
                    (navigationController?.getSystemBars()?.bottom ?: 0),
                    (window?.imeInsets?.bottom ?: 0)
                )
            )
        }
        addressInputView.insetsUpdated()
    }

    override fun onBackPressed(): Boolean {
        if (addressInputView.inputFieldHasFocus()) {
            clearAddressFocus()
            hideSuggestions()
            return false
        }
        if (suggestionsBoxView.isVisible) {
            hideSuggestions()
            return false
        }
        return super.onBackPressed()
    }

    override fun showError(error: MBridgeError?) {
        super.showError(error)
        sentNftAddress = null
    }

    override fun feeUpdated(fee: BigInteger?, err: MBridgeError?) {
        if (fee == null && err == null) {
            continueButton.isLoading = true
            return
        }

        val nativeToken = TokenStore.getToken(chain.nativeSlug)
        val feeString = if (fee != null && nativeToken != null) {
            fee.toString(
                decimals = nativeToken.decimals,
                currency = nativeToken.symbol,
                currencyDecimals = fee.smartDecimalsCount(nativeToken.decimals),
                showPositiveSign = false
            )
        } else {
            null
        }
        feeLabel.text = feeString?.let {
            LocaleController.getString("\$fee_value_with_colon").replace("%fee%", it)
        }
        val shouldShowFee = !feeLabel.text.isNullOrBlank()
        feeLabel.visibility =
            if (shouldShowFee && !suggestionsBoxView.isVisible) View.VISIBLE else View.GONE

        continueButton.isLoading = false
        continueButton.isEnabled = err == null
        continueButton.text = err?.toLocalized ?: title
    }

    override fun addressInfoUpdated(info: SendNftVM.AddressInfo?) {
        val destination = viewModel.inputAddress.trim()
        if (destination.isEmpty()) {
            return
        }
        if (info?.input == destination) {
            updateAddressOverlay(info, destination)
        }
    }

    override fun addressSearchCandidatesChanged(enabled: Boolean) {
        suggestionsBoxView.isEnabled = enabled
    }

    private fun clearAddressFocus() {
        if (addressInputView.inputFieldHasFocus()) {
            addressInputView.resetInputFieldFocus()
        }
        view.hideKeyboard()
    }

    private fun showSuggestions() {
        if (!suggestionsBoxView.isEnabled) {
            return
        }
        if (primaryContent.isGone && suggestionsBoxView.isVisible) {
            return
        }
        suggestionAnimator?.cancel()
        val dy = 32f.dp
        val shouldShowFee = !feeLabel.text.isNullOrBlank()

        with(primaryContent) {
            isVisible = true
            alpha = 1f
            translationY = 0f
        }
        with(suggestionsBoxView) {
            isVisible = true
            alpha = 0f
            translationY = -dy
        }
        with(continueButton) {
            isVisible = true
            alpha = 1f
            translationY = 0f
        }
        with(feeLabel) {
            isVisible = shouldShowFee
            alpha = 1f
            translationY = 0f
        }

        val onEnd = {
            with(primaryContent) {
                isGone = true
                alpha = 0f
                translationY = dy
            }
            with(suggestionsBoxView) {
                alpha = 1f
                translationY = 0f
            }
            with(continueButton) {
                isGone = true
                alpha = 0f
                translationY = dy
            }
            with(feeLabel) {
                isGone = true
                alpha = 0f
                translationY = dy
            }
            scrollView.scrollTo(0, 0)
        }

        if (!WGlobalStorage.getAreAnimationsActive()) {
            onEnd()
            return
        }

        suggestionAnimator = animatorSet {
            together {
                duration(AnimationConstants.NAV_PUSH)
                interpolator(WInterpolator.emphasized)
                viewProperty(primaryContent) {
                    alpha(0f)
                    translationY(dy)
                }
                viewProperty(suggestionsBoxView) {
                    alpha(1f)
                    translationY(0f)
                }
                viewProperty(continueButton) {
                    alpha(0f)
                    translationY(dy)
                }
                if (shouldShowFee) {
                    viewProperty(feeLabel) {
                        alpha(0f)
                        translationY(dy)
                    }
                }
                intValues(scrollView.scrollY, 0) {
                    onUpdate { animatedValue ->
                        scrollView.scrollTo(0, animatedValue)
                    }
                }
            }
            onEnd { onEnd() }
        }.apply { start() }
    }

    private fun hideSuggestions() {
        if (!suggestionsBoxView.isEnabled) {
            return
        }
        if (primaryContent.isVisible && !suggestionsBoxView.isVisible) {
            return
        }
        suggestionAnimator?.cancel()
        val dy = 32f.dp
        val shouldShowFee = !feeLabel.text.isNullOrBlank()

        with(primaryContent) {
            isVisible = true
            alpha = 0f
            translationY = dy
        }
        with(suggestionsBoxView) {
            isVisible = true
            alpha = 1f
            translationY = 0f
        }
        with(continueButton) {
            isVisible = true
            alpha = 0f
            translationY = dy
        }
        with(feeLabel) {
            isVisible = shouldShowFee
            alpha = 0f
            translationY = dy
        }

        val onEnd = {
            with(primaryContent) {
                alpha = 1f
                translationY = 0f
            }
            with(suggestionsBoxView) {
                isGone = true
                alpha = 0f
                translationY = -dy
            }
            with(continueButton) {
                alpha = 1f
                translationY = 0f
            }
            with(feeLabel) {
                isVisible = shouldShowFee
                alpha = 1f
                translationY = 0f
            }
        }

        if (!WGlobalStorage.getAreAnimationsActive()) {
            onEnd()
            return
        }

        suggestionAnimator = animatorSet {
            together {
                duration(AnimationConstants.NAV_PUSH)
                interpolator(WInterpolator.emphasized)
                viewProperty(primaryContent) {
                    alpha(1f)
                    translationY(0f)
                }
                viewProperty(suggestionsBoxView) {
                    alpha(0f)
                    translationY(-dy)
                }
                viewProperty(continueButton) {
                    alpha(1f)
                    translationY(0f)
                }
                if (shouldShowFee) {
                    viewProperty(feeLabel) {
                        alpha(1f)
                        translationY(0f)
                    }
                }
            }
            onEnd { onEnd() }
        }.apply { start() }
    }

    private fun updateAddressOverlay(info: SendNftVM.AddressInfo, destination: String) {
        val resolved = info.resolvedAddress
        val name = info.addressName
        val isScam = info.isScam == true
        updateContinueButtonType(isScam)

        if (isScam) {
            val address = resolved ?: destination
            addressInputView.setScamAddress(
                MSavedAddress(
                    address = address,
                    name = address,
                    chain = info.chain.name
                )
            )
            return
        }

        if (!resolved.isNullOrEmpty() && !name.isNullOrEmpty()) {
            addressInputView.setAddress(
                MSavedAddress(
                    address = resolved,
                    name = name,
                    chain = info.chain.name
                )
            )
            return
        }

        if (addressInputView.getKeyword() != destination) {
            addressInputView.setText(destination)
        }
    }

    private fun updateContinueButtonType(isScam: Boolean) {
        continueButton.type = if (isScam) {
            WButton.Type.DESTRUCTIVE
        } else {
            WButton.Type.PRIMARY
        }
    }

    private var sentNftAddress: String? = null
    private fun checkReceivedActivity(receivedActivity: MApiTransaction) {
        if (sentNftAddress == null) {
            return
        }

        val txMatch =
            receivedActivity is MApiTransaction.Transaction && receivedActivity.nft?.address == sentNftAddress
        if (!txMatch) {
            return
        }

        sentNftAddress = null
        WalletCore.unregisterObserver(this)
        if (window?.topNavigationController != navigationController) {
            window?.dismissNav(navigationController)
            return
        }
        if ((window?.navigationControllers?.size ?: 0) > 1) {
            window?.dismissLastNav {
                WalletCore.notifyEvent(
                    WalletEvent.OpenActivity(
                        displayedAccount.accountId!!,
                        receivedActivity
                    )
                )
            }
        } else {
            navigationController?.popToRoot {
                WalletCore.notifyEvent(
                    WalletEvent.OpenActivity(
                        displayedAccount.accountId!!,
                        receivedActivity
                    )
                )
            }
        }
    }

    override fun onWalletEvent(walletEvent: WalletEvent) {
        when (walletEvent) {
            is WalletEvent.NewLocalActivities -> {
                walletEvent.localActivities?.forEach {
                    checkReceivedActivity(it)
                }
            }

            is WalletEvent.ReceivedPendingActivities -> {
                walletEvent.pendingActivities?.forEach {
                    checkReceivedActivity(it)
                }
            }

            is WalletEvent.AccountSavedAddressesChanged -> {
                suggestionsBoxView.search(addressInputView.getKeyword())
            }

            else -> {}
        }
    }
}
