package org.mytonwallet.app_air.uisend.send

import android.animation.Animator
import android.annotation.SuppressLint
import android.content.Context
import android.os.Build
import android.text.Editable
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.TextWatcher
import android.util.TypedValue
import android.view.Gravity
import android.view.View.generateViewId
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.Space
import androidx.appcompat.widget.AppCompatEditText
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.constraintlayout.widget.Guideline
import androidx.core.content.ContextCompat
import androidx.core.view.isGone
import androidx.core.view.isInvisible
import androidx.core.view.isVisible
import androidx.core.view.updateLayoutParams
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.launch
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.adapter.implementation.holders.ListGapCell
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.base.WViewControllerWithModelStore
import org.mytonwallet.app_air.uicomponents.base.showAlert
import org.mytonwallet.app_air.uicomponents.commonViews.AddressInputLayout
import org.mytonwallet.app_air.uicomponents.commonViews.ReversedCornerViewUpsideDown
import org.mytonwallet.app_air.uicomponents.commonViews.TokenAmountInputView
import org.mytonwallet.app_air.uicomponents.commonViews.cells.HeaderCell
import org.mytonwallet.app_air.uicomponents.commonViews.feeDetailsDialog.FeeDetailsDialog
import org.mytonwallet.app_air.uicomponents.extensions.animatorSet
import org.mytonwallet.app_air.uicomponents.extensions.collectFlow
import org.mytonwallet.app_air.uicomponents.extensions.disableInteraction
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.extensions.setReadOnly
import org.mytonwallet.app_air.uicomponents.helpers.DieselAuthorizationHelpers
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.viewControllers.SendTokenVC
import org.mytonwallet.app_air.uicomponents.widgets.CopyTextView
import org.mytonwallet.app_air.uicomponents.widgets.WAlertLabel
import org.mytonwallet.app_air.uicomponents.widgets.WButton
import org.mytonwallet.app_air.uicomponents.widgets.WFrameLayout
import org.mytonwallet.app_air.uicomponents.widgets.autoComplete.WAutoCompleteAddressView
import org.mytonwallet.app_air.uicomponents.widgets.clearSegmentedControl.WClearSegmentedControl
import org.mytonwallet.app_air.uicomponents.widgets.dialog.WDialog
import org.mytonwallet.app_air.uicomponents.widgets.hideKeyboard
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup.BackgroundStyle
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uicomponents.widgets.setRoundedOutline
import org.mytonwallet.app_air.uicomponents.widgets.showKeyboard
import org.mytonwallet.app_air.uicomponents.widgets.updateLayoutParamsIfExists
import org.mytonwallet.app_air.uisend.send.helpers.ScamDetectionHelpers
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.helpers.WInterpolator
import org.mytonwallet.app_air.walletcontext.utils.CoinUtils
import org.mytonwallet.app_air.walletcontext.utils.VerticalImageSpan
import org.mytonwallet.app_air.walletcore.JSWebViewBridge
import org.mytonwallet.app_air.walletcore.PRICELESS_TOKEN_HASHES
import org.mytonwallet.app_air.walletcore.STAKED_MYCOIN_SLUG
import org.mytonwallet.app_air.walletcore.STAKED_USDE_SLUG
import org.mytonwallet.app_air.walletcore.STAKE_SLUG
import org.mytonwallet.app_air.walletcore.TONCOIN_SLUG
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.helpers.ActivityHelpers
import org.mytonwallet.app_air.walletcore.models.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.MApiTransaction
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.ConfigStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore
import java.lang.ref.WeakReference
import java.math.BigInteger
import kotlin.math.max
import kotlin.math.roundToInt

@SuppressLint("ViewConstructor")
class SendVC(
    context: Context,
    private val initialTokenSlug: String? = null,
    private val initialValues: InitialValues? = null,
    private val autoConfirm: Boolean = false,
) : WViewControllerWithModelStore(context), WalletCore.EventObserver {
    override val TAG = "Send"

    override val displayedAccount =
        DisplayedAccount(AccountStore.activeAccountId, AccountStore.isPushedTemporary)

    private val activeAccount = AccountStore.activeAccount

    private val viewModel by lazy { ViewModelProvider(this)[SendViewModel::class.java] }

    data class InitialValues(
        val address: String?,
        val amount: String? = null,
        val binary: String? = null,
        val comment: String? = null,
        val init: String? = null,
    )

    private val isOffRampAllowed: Boolean
        get() {
            return activeAccount?.supportsBuyWithCard == true && ConfigStore.isLimited != true
        }

    private val shouldShowSellTab: Boolean
        get() = !autoConfirm && isOffRampAllowed

    private var didAutoConfirm = false

    private val navSegmentedControl by lazy {
        WClearSegmentedControl(context).apply {
            paintColor = WColor.Background.color
            setItems(
                buildSegmentedItems(), 0, object : WClearSegmentedControl.Delegate {
                    override fun onIndexChanged(to: Int, animated: Boolean) {
                        if (shouldShowSellTab && to == 1) {
                            openSellWithCard()
                            updateThumbPosition(
                                position = 0f,
                                targetPosition = 0,
                                animated = false,
                                force = true,
                                isAnimatingToPosition = false
                            )
                        }
                    }

                    override fun onItemMoved(from: Int, to: Int) {}

                    override fun enterReorderingMode() {}
                })
        }
    }

    private var suggestionAnimator: Animator? = null
    private var showSuggestionAnimatorInProgress: Boolean = false
    private val continueButtonHeightPx: Int = 50.dp
    private val continueButtonVerticalMarginPx: Int = 15.dp
    private val continueButtonSpaceHeightPx: Int =
        continueButtonHeightPx + continueButtonVerticalMarginPx * 2

    private val topGap = Space(context)

    private val bottomGuideline = Guideline(context).apply {
        id = generateViewId()
    }

    private val title1: HeaderCell by lazy {
        HeaderCell(context).apply {
            configure(
                title = LocaleController.getString("Send to"),
                titleColor = WColor.Tint,
                topRounding = HeaderCell.TopRounding.FIRST_ITEM
            )
        }
    }

    private val gap1 by lazy { Space(context) }

    private val amountInputView by lazy {
        TokenAmountInputView(context, isFirstItem = false).apply {
            id = generateViewId()
        }
    }
    private val addressInputView by lazy {
        AddressInputLayout(
            WeakReference(this),
            AddressInputLayout.AutoCompleteConfig(
                type = AddressInputLayout.AutoCompleteConfig.Type.EXTERNAL
            ),
            onTextEntered = { keyword ->
                hideSuggestions()
                focusAmount()
                suggestionsBoxView.search(keyword, true)
            }).apply {
            id = generateViewId()
            showCloseOnTextEditing = true
            focusCallback = { hasFocus ->
                if (hasFocus) {
                    showSuggestions()
                    suggestionsBoxView.search(getKeyword())
                }
            }
            addTextChangedListener { input ->
                suggestionsBoxView.search(input)
            }
            textFieldTopPadding = 19.dp
            textFieldBottomPadding = 14.dp
        }
    }

    private val suggestionsBoxView: WAutoCompleteAddressView by lazy {
        WAutoCompleteAddressView(context).apply {
            autoCompleteConfig = AddressInputLayout.AutoCompleteConfig(
                type = AddressInputLayout.AutoCompleteConfig.Type.EXTERNAL
            )
            search("")
            isGone = true
            setRoundedOutline(ViewConstants.BLOCK_RADIUS.dp)
            onSelected = { account, savedAddress ->
                when {
                    account != null -> {
                        addressInputView.setAccount(account)
                        hideSuggestions()
                        focusAmount()
                    }

                    savedAddress != null -> {
                        addressInputView.setAddress(savedAddress)
                        hideSuggestions()
                        focusAmount()
                    }
                }
            }
            viewController = WeakReference(this@SendVC)
        }
    }

    private val gap2 by lazy { ListGapCell(context, ViewConstants.GAP.dp) }

    private val title2 = HeaderCell(context).apply {
        setOnClickListener {
            if (AccountStore.activeAccount?.supportsCommentEncryption != true)
                return@setOnClickListener
            WMenuPopup.present(
                this@apply,
                listOf(
                    WMenuPopup.Item(
                        null,
                        LocaleController.getString("Comment or Memo"),
                        false,
                    ) {
                        viewModel.onShouldEncrypt(false)
                        updateCommentTitleLabel()
                    },
                    WMenuPopup.Item(
                        null,
                        LocaleController.getString("Encrypted Message"),
                        false,
                    ) {
                        viewModel.onShouldEncrypt(true)
                        updateCommentTitleLabel()
                    }),
                xOffset = 0,
                yOffset = 5.dp,
                popupWidth = WRAP_CONTENT,
                positioning = WMenuPopup.Positioning.BELOW,
                windowBackgroundStyle = BackgroundStyle.Cutout.fromView(
                    titleLabel,
                    roundRadius = 16f.dp,
                    horizontalOffset = 8.dp,
                    verticalOffset = 5.dp
                )
            )
        }
    }

    private val commentInputView by lazy {
        AppCompatEditText(context).apply {
            id = generateViewId()
            background = null
            hint = LocaleController.getString("Add a message, if needed")
            typeface = WFont.Regular.typeface
            layoutParams =
                ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT)
            setPaddingDp(20, 20, 20, 14)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                setLineHeight(TypedValue.COMPLEX_UNIT_SP, 24f)
            }
        }
    }

    private val signatureWarningGap by lazy { ListGapCell(context, ViewConstants.GAP.dp) }

    private val signatureWarning by lazy {
        WAlertLabel(
            context,
            LocaleController.getString("\$signature_warning"),
            WColor.Red.color,
            coloredText = true
        )
    }

    private val binaryMessageGap by lazy { ListGapCell(context, ViewConstants.GAP.dp) }

    private val binaryMessageTitle by lazy {
        HeaderCell(context).apply {
            configure(
                title = LocaleController.getString("Signing Data"),
                titleColor = WColor.Tint,
                topRounding = HeaderCell.TopRounding.FIRST_ITEM
            )
        }
    }

    private val binaryMessageView by lazy {
        CopyTextView(context).apply {
            id = generateViewId()
            typeface = WFont.Regular.typeface
            layoutParams = LinearLayout.LayoutParams(
                MATCH_PARENT,
                WRAP_CONTENT
            )
            setPaddingDp(20, 14, 20, 14)

            setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
            setLineHeight(TypedValue.COMPLEX_UNIT_SP, 24f)
            text = initialValues?.binary
            clipLabel = LocaleController.getString("Signing Data")
            clipToast = LocaleController.getString("Data was copied!")
        }
    }

    private val initDataGap by lazy { ListGapCell(context, ViewConstants.GAP.dp) }

    private val initDataTitle by lazy {
        HeaderCell(context).apply {
            configure(
                title = LocaleController.getString("Contract Initialization Data"),
                titleColor = WColor.Tint,
                topRounding = HeaderCell.TopRounding.FIRST_ITEM
            )
        }
    }

    private val initDataView by lazy {
        CopyTextView(context).apply {
            id = generateViewId()
            typeface = WFont.Regular.typeface
            layoutParams = LinearLayout.LayoutParams(
                MATCH_PARENT,
                WRAP_CONTENT
            )
            setPaddingDp(20, 14, 20, 14)

            setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
            setLineHeight(TypedValue.COMPLEX_UNIT_SP, 24f)
            text = initialValues?.init
            clipLabel = LocaleController.getString("Contract Initialization Data")
            clipToast = LocaleController.getString("Contract Initialization Data was copied!")
        }
    }

    private val headerContentContainer by lazy {
        LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL

            addView(
                topGap,
                ViewGroup.LayoutParams(
                    MATCH_PARENT,
                    (navigationController?.getSystemBars()?.top ?: 0) +
                        WNavigationBar.DEFAULT_HEIGHT.dp
                )
            )
            addView(title1, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
            addView(
                addressInputView,
                LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT)
            )
            addView(gap1, ViewGroup.LayoutParams(WRAP_CONTENT, ViewConstants.GAP.dp))
        }
    }

    private val primaryContent by lazy {
        LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL

            val hasBinary = initialValues?.binary != null
            val hasInit = initialValues?.init != null

            addView(
                amountInputView,
                ConstraintLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT)
            )
            if (!hasBinary) {
                addView(gap2)
                addView(title2, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
                addView(
                    commentInputView,
                    ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT)
                )
            }
            if (hasBinary) {
                addView(signatureWarningGap)
                addView(signatureWarning)
                // ^ It is better to place this one here, otherwise users may not scroll down enough to see it
                addView(binaryMessageGap)
                addView(binaryMessageTitle)
                addView(binaryMessageView)
            }
            if (hasInit) {
                addView(initDataGap)
                addView(initDataTitle)
                addView(initDataView)
            }
        }
    }

    private val dynamicContentContainer: WFrameLayout by lazy {
        WFrameLayout(context).apply {
            clipChildren = false
            addView(primaryContent, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
            addView(suggestionsBoxView, LinearLayout.LayoutParams(MATCH_PARENT, 0))
        }
    }

    private val linearLayout by lazy {
        LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            clipChildren = false
            addView(headerContentContainer, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
            addView(dynamicContentContainer, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        }
    }

    private val scrollView by lazy {
        ScrollView(context).apply {
            addView(
                linearLayout,
                ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT)
            )
            id = generateViewId()
            setOnScrollChangeListener { _, _, scrollY, _, _ ->
                updateBlurViews(scrollView = this, computedOffset = scrollY)
                if (scrollY > 0) {
                    bottomReversedCornerViewUpsideDown.resumeBlurring()
                } else {
                    bottomReversedCornerViewUpsideDown.pauseBlurring()
                }
            }
            overScrollMode = ScrollView.OVER_SCROLL_ALWAYS
            isVerticalScrollBarEnabled = false
        }
    }

    private val continueButton by lazy {
        WButton(context).apply {
            id = generateViewId()
        }
    }

    private val continueButtonSpace by lazy {
        Space(context).apply {
            id = generateViewId()
        }
    }

    private val bottomReversedCornerViewUpsideDown: ReversedCornerViewUpsideDown by lazy {
        ReversedCornerViewUpsideDown(context, scrollView).apply {
            if (ignoreSideGuttering) {
                setHorizontalPadding(0f)
            }
        }
    }

    private val onInputCommentTextWatcher = object : TextWatcher {
        override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
        override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {
            viewModel.onInputComment(s?.toString() ?: "")
        }

        override fun afterTextChanged(s: Editable?) {}
    }

    private val onInputDestinationTextWatcher = object : TextWatcher {
        override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
        override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {
            val address = s?.toString() ?: ""
            viewModel.onInputDestination(address)
            switchTokenBasedOnChain(address)
        }

        override fun afterTextChanged(s: Editable?) {}
    }

    private val onAmountTextWatcher = object : TextWatcher {
        override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
        override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {
            viewModel.onInputAmount(s?.toString() ?: "")
        }

        override fun afterTextChanged(s: Editable?) {}
    }

    private fun focusAmount() {
        amountInputView.amountEditText.requestFocus()
        amountInputView.amountEditText.showKeyboard()
    }

    override fun onBackPressed(): Boolean {
        if (addressInputView.inputFieldHasFocus()) {
            addressInputView.resetInputFieldFocus()
            hideSuggestions()
            return false
        }
        if (suggestionsBoxView.isVisible) {
            hideSuggestions()
            return false
        }
        return super.onBackPressed()
    }

    private fun showSuggestions() {
        if (!suggestionsBoxView.isEnabled) {
            return
        }
        if (primaryContent.isGone && suggestionsBoxView.isVisible) {
            return
        }
        suggestionAnimator?.cancel()
        navigationBar?.fadeInActions()
        val dy = 32f.dp
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
        continueButtonSpace.updateLayoutParams {
            height = continueButtonSpaceHeightPx
        }
        updateBottomOffsets(true)
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
                translationY = continueButtonSpaceHeightPx.toFloat()
            }
            continueButtonSpace.updateLayoutParams {
                height = 1
            }
            updateBottomOffsets(false)
            scrollView.scrollTo(0, 0)
            showSuggestionAnimatorInProgress = false
            insetsUpdated()
        }
        if (!WGlobalStorage.getAreAnimationsActive()) {
            onEnd()
            return
        }
        showSuggestionAnimatorInProgress = true
        val cornerViewDiff = getBottomReversedCornerViewUpsideDownHeight(true) -
            getBottomReversedCornerViewUpsideDownHeight(false)
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
                    translationY(continueButtonSpaceHeightPx.toFloat())
                }
                intValues(scrollView.scrollY, 0) {
                    onUpdate { animatedValue ->
                        scrollView.scrollTo(0, animatedValue)
                    }
                }
                intValues(continueButtonSpace.height, 1) {
                    onUpdate { animatedValue ->
                        continueButtonSpace.updateLayoutParams { height = animatedValue }
                    }
                }
                intValues(cornerViewDiff, 0) {
                    onUpdate { animatedValue -> updateBottomOffsets(false, animatedValue) }
                }
            }
            onEnd { onEnd() }
        }.apply { start() }
    }

    private fun hideSuggestions() {
        if (!suggestionsBoxView.isEnabled) {
            return
        }
        if (primaryContent.isVisible && suggestionsBoxView.isInvisible) {
            return
        }
        navigationBar?.fadeOutActions()
        suggestionAnimator?.cancel()
        val dy = 32f.dp
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
            translationY = continueButtonSpaceHeightPx.toFloat()
        }
        continueButtonSpace.updateLayoutParams {
            height = 1
        }
        updateBottomOffsets(false)
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
            continueButtonSpace.updateLayoutParams {
                height = continueButtonSpaceHeightPx
            }
            updateBottomOffsets(true)
            continueButton.translationY = 0f
        }
        if (!WGlobalStorage.getAreAnimationsActive()) {
            onEnd()
            return
        }
        val cornerViewDiff = getBottomReversedCornerViewUpsideDownHeight(true) -
            getBottomReversedCornerViewUpsideDownHeight(false)
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
                intValues(0, continueButtonSpaceHeightPx) {
                    onUpdate { animatedValue ->
                        continueButtonSpace.updateLayoutParams { height = animatedValue }
                    }
                }
                intValues(0, cornerViewDiff) {
                    onUpdate { animatedValue -> updateBottomOffsets(false, animatedValue) }
                }
            }
            onEnd { onEnd() }
        }.apply { start() }
    }

    override fun setupViews() {
        super.setupViews()

        WalletCore.registerObserver(this)

        setupNavBar(true)
        navigationBar?.setTitleView(navSegmentedControl, animated = false)
        navigationBar?.addCloseButton()
        navigationBar?.setTitleGravity(Gravity.CENTER)

        view.addHorizontalGuideline(bottomGuideline)
        view.addView(scrollView, ViewGroup.LayoutParams(MATCH_PARENT, 0))
        view.addView(
            bottomReversedCornerViewUpsideDown,
            FrameLayout.LayoutParams(
                MATCH_PARENT,
                getBottomReversedCornerViewUpsideDownHeight()
            ).apply {
                gravity = Gravity.BOTTOM
            }
        )
        scrollView.addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ ->
            val suggestionsBoxHeight =
                (scrollView.height - linearLayout.paddingBottom) - headerContentContainer.height
            if (suggestionsBoxView.layoutParams.height != suggestionsBoxHeight) {
                suggestionsBoxView.updateLayoutParams { height = suggestionsBoxHeight }
            }
        }
        view.addView(
            continueButtonSpace, ViewGroup.LayoutParams(MATCH_PARENT, continueButtonSpaceHeightPx)
        )
        view.addView(continueButton, ViewGroup.LayoutParams(MATCH_PARENT, continueButtonHeightPx))
        view.setConstraints {
            allEdges(scrollView)
            toCenterX(bottomReversedCornerViewUpsideDown)
            toBottom(bottomReversedCornerViewUpsideDown)
            bottomToTop(continueButtonSpace, bottomGuideline)
            toCenterX(continueButtonSpace)
            toCenterX(continueButton, 20f)
            bottomToTopPx(continueButton, bottomGuideline, continueButtonVerticalMarginPx)
            guidelineEndPx(bottomGuideline, getSystemBottomOffset())
        }

        initialTokenSlug?.let {
            viewModel.onInputToken(it)
            updateCommentViews()
            showServiceTokenWarningIfRequired()
        }

        continueButton.setOnClickListener {
            if (viewModel.shouldAuthorizeDiesel()) {
                DieselAuthorizationHelpers.authorizeDiesel(context)
                return@setOnClickListener
            }
            openConfirmIfPossible()
        }

        if (!autoConfirm) {
            addressInputView.addTextChangedListener(onInputDestinationTextWatcher)
            addressInputView.doAfterQrCodeScanned { address ->
                switchTokenBasedOnChain(address)
            }

            commentInputView.addTextChangedListener(onInputCommentTextWatcher)

            amountInputView.doOnMaxButtonClick(viewModel::onInputMaxButton)
            amountInputView.doOnEquivalentButtonClick(viewModel::onInputToggleFiatMode)
            amountInputView.doOnFeeButtonClick {
                lateinit var dialogRef: WDialog
                dialogRef = FeeDetailsDialog.create(
                    context,
                    TokenStore.getToken(viewModel.getTokenSlug())!!,
                    viewModel.getConfirmationPageConfig()!!.explainedFee!!
                ) {
                    dialogRef.dismiss()
                }
                dialogRef.presentOn(this)
            }
            amountInputView.amountEditText.addTextChangedListener(onAmountTextWatcher)
            amountInputView.tokenSelectorView.setOnClickListener {
                push(SendTokenVC(context).apply {
                    setOnAssetSelectListener {
                        MBlockchain.valueOfSlugOrNull(it.slug)?.let { blockchain ->
                            addressInputView.activeChain = blockchain
                        }
                        viewModel.onInputToken(it.slug)
                        updateCommentViews()
                        showServiceTokenWarningIfRequired()
                    }
                })
            }
        }

        collectFlow(viewModel.inputStateFlow) {
            if (amountInputView.amountEditText.text.toString() != it.amount) {
                amountInputView.amountEditText.setText(it.amount)
            }
        }

        collectFlow(viewModel.uiStateFlow) {
            amountInputView.set(
                it.uiInput,
                (viewModel.getConfirmationPageConfig()?.explainedFee?.excessFee
                    ?: BigInteger.ZERO) > BigInteger.ZERO
            )
            continueButton.isLoading = it.uiButton.status.isLoading
            if (!it.uiButton.status.isLoading) {
                continueButton.isEnabled = it.uiButton.status.isEnabled
                continueButton.isError = it.uiButton.status.isError
                continueButton.text = it.uiButton.title
            }
            if (it.uiButton.status == SendViewModel.ButtonStatus.NotEnoughNativeToken) {
                showScamWarningIfRequired()
            }

            if (autoConfirm &&
                !didAutoConfirm &&
                it.uiButton.status == SendViewModel.ButtonStatus.Ready
            ) {
                didAutoConfirm = true
                openConfirmIfPossible()
            }
            suggestionsBoxView.isEnabled = it.uiAddressSearch.enabled
        }

        collectFlow(viewModel.uiEventFlow) { event ->
            when (event) {
                is SendViewModel.UiEvent.ShowAlert -> {
                    showAlert(event.title, event.message)
                }
            }
        }

        updateTheme()
        setInitialValues()
        if (autoConfirm) {
            applyReadonlyMode()
        }
    }

    private fun buildSegmentedItems(): List<WClearSegmentedControl.Item> {
        val items = mutableListOf(
            WClearSegmentedControl.Item(LocaleController.getString("Send"), null, null)
        )
        if (shouldShowSellTab) {
            items.add(WClearSegmentedControl.Item(LocaleController.getString("Sell"), null, null))
        }
        return items
    }

    private fun openSellWithCard() {
        if (!isOffRampAllowed || autoConfirm) return
        val activeAccount = activeAccount ?: return
        SellWithCardLauncher.launch(
            caller = WeakReference(this),
            account = activeAccount,
            tokenSlug = viewModel.getTokenSlug(),
        )
    }

    private fun applyReadonlyMode() {
        addressInputView.setEditable(false)
        amountInputView.apply {
            amountEditText.setReadOnly()
            tokenSelectorView.disableInteraction()
        }
        commentInputView.setReadOnly()
        title2.setOnClickListener(null)
    }

    private fun openConfirmIfPossible() {
        viewModel.getConfirmationPageConfig()?.let { config ->
            val vc = SendConfirmVC(
                context = context,
                config = config,
                transferOptions = viewModel.getTransferOptions(config, ""),
                slug = viewModel.getTokenSlug(),
                name = addressInputView.autocompleteResult?.name
            )
            val isHardware = AccountStore.activeAccount?.isHardware == true
            vc.setNextTask { passcode ->
                lifecycleScope.launch {
                    if (isHardware) {
                        // Sent using LedgerConnect
                    } else {
                        // Send with passcode
                        try {
                            val id = viewModel.callSend(config, passcode!!).activityId
                            sentActivityId = ActivityHelpers.getTxIdFromId(id)
                            // Wait for Pending Activity event...
                            receivedLocalActivities?.firstOrNull { it.getTxHash() == sentActivityId }
                                ?.let {
                                    checkReceivedActivity(it)
                                }
                        } catch (e: JSWebViewBridge.ApiError) {
                            navigationController?.viewControllers[navigationController!!.viewControllers.size - 2]?.showError(
                                e.parsed
                            )
                            navigationController?.pop(true)
                        }
                    }
                }
            }
            view.hideKeyboard()
            push(vc)
        }
    }

    override fun updateTheme() {
        super.updateTheme()
        view.setBackgroundColor(WColor.SecondaryBackground.color)
        navSegmentedControl.paintColor = WColor.Background.color
        scrollView.setBackgroundColor(WColor.SecondaryBackground.color)
        listOf(binaryMessageTitle, initDataTitle).forEach {
            it.setBackgroundColor(
                WColor.Background.color,
                ViewConstants.BLOCK_RADIUS.dp,
                0f,
            )
        }
        title1.updateTheme()
        title2.updateTheme()
        val dataViews = listOf(addressInputView, commentInputView, binaryMessageView, initDataView)
        dataViews.forEach {
            it.setBackgroundColor(
                WColor.Background.color,
                0f,
                ViewConstants.BLOCK_RADIUS.dp
            )
        }
        commentInputView.setTextColor(WColor.PrimaryText.color)
        commentInputView.setHintTextColor(WColor.SecondaryText.color)

        updateCommentTitleLabel()
    }

    private fun updateCommentTitleLabel() {
        title2.apply {
            if (AccountStore.activeAccount?.supportsCommentEncryption == false) {
                configure(
                    title = LocaleController.getString("Comment or Memo"),
                    titleColor = WColor.Tint,
                    topRounding = HeaderCell.TopRounding.FIRST_ITEM
                )
                return@apply
            }
            val txt =
                LocaleController.getString(if (viewModel.getShouldEncrypt()) "Encrypted Message" else "Comment or Memo") + " "
            val ss = SpannableStringBuilder(txt)
            ContextCompat.getDrawable(
                context,
                org.mytonwallet.app_air.icons.R.drawable.ic_arrow_bottom_8
            )?.let { drawable ->
                drawable.mutate()
                drawable.setTint(WColor.Tint.color)
                val width = 8.dp
                val height = 4.dp
                drawable.setBounds(0, 0, width, height)
                val imageSpan = VerticalImageSpan(drawable)
                ss.append(" ", imageSpan, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            }
            configure(
                title = ss,
                titleColor = WColor.Tint,
                topRounding = HeaderCell.TopRounding.FIRST_ITEM
            )
        }
    }

    private fun setInitialValues() {
        initialValues?.let {
            it.address?.let { address ->
                viewModel.onInputDestination(address)
                addressInputView.setText(address)
            }
            it.amount?.let { amountBigDecimalString ->
                val token = TokenStore.getToken(initialTokenSlug ?: TONCOIN_SLUG)
                token?.let {
                    CoinUtils.fromDecimal(amountBigDecimalString, token.decimals)
                        ?.let { amountBigInt ->
                            val amountToSet = CoinUtils.toBigDecimal(
                                amountBigInt,
                                token.decimals
                            ).stripTrailingZeros().toPlainString()
                            viewModel.onInputAmount(amountToSet)
                        }
                }
            }
            it.comment?.let { comment ->
                if (it.binary == null) {
                    viewModel.onInputComment(comment)
                    commentInputView.setText(comment)
                }
            }
            it.binary?.let { binary ->
                viewModel.setBinaryData(binary)
            }
            it.init?.let { init ->
                viewModel.setStateInit(init)
            }
        }
    }

    private fun getSystemBottomOffset(): Int {
        return max(
            (navigationController?.getSystemBars()?.bottom ?: 0),
            (window?.imeInsets?.bottom ?: 0)
        )
    }

    private fun getScrollViewBottomMargin(buttonVisible: Boolean = true): Int {
        val system = getSystemBottomOffset()
        val button = if (buttonVisible) {
            continueButtonSpaceHeightPx
        } else {
            0
        }
        return system + button
    }

    private fun getBottomReversedCornerViewUpsideDownHeight(buttonVisible: Boolean = true): Int {
        val system = getSystemBottomOffset()
        val button = if (buttonVisible) {
            continueButtonSpaceHeightPx
        } else {
            ViewConstants.GAP.dp
        }
        val radius = ViewConstants.BLOCK_RADIUS.dp.roundToInt()
        return system + button + radius
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        scrollView.setPadding(
            ViewConstants.HORIZONTAL_PADDINGS.dp,
            0,
            ViewConstants.HORIZONTAL_PADDINGS.dp,
            0
        )
        topGap.updateLayoutParamsIfExists {
            height = (navigationController?.getSystemBars()?.top ?: 0) +
                WNavigationBar.DEFAULT_HEIGHT.dp
        }
        addressInputView.insetsUpdated()
        if (showSuggestionAnimatorInProgress) {
            return
        }
        updateBottomOffsets(continueButton.isVisible)
        view.setConstraints {
            guidelineEndPx(bottomGuideline, getSystemBottomOffset())
        }
    }

    private fun updateBottomOffsets(buttonVisible: Boolean, extraSize: Int = 0) {
        bottomReversedCornerViewUpsideDown.updateLayoutParamsIfExists {
            height = getBottomReversedCornerViewUpsideDownHeight(buttonVisible) + extraSize
        }
        linearLayout.setPadding(0, 0, 0, getScrollViewBottomMargin(buttonVisible) + extraSize)
    }

    private fun updateCommentViews() {
        val isCommentSupported =
            TokenStore.getToken(viewModel.getTokenSlug())?.mBlockchain?.isCommentSupported
        title2.isGone = isCommentSupported != true
        commentInputView.isGone = title2.isGone
        if (isCommentSupported != true) {
            commentInputView.text = null
        }
    }

    private fun showScamWarningIfRequired() {
        TokenStore.getToken(viewModel.getTokenSlug())?.mBlockchain?.let { blockchain ->
            if (ScamDetectionHelpers.shouldShowSeedPhraseScamWarning(blockchain)) {
                WGlobalStorage.removeAccountImportedAt(AccountStore.activeAccountId!!)
                AccountStore.activeAccount?.importedAt = null
                showAlert(
                    LocaleController.getString("Warning!"),
                    ScamDetectionHelpers.scamWarningMessage(),
                    button = LocaleController.getString("Got It"),
                    primaryIsDanger = true,
                    allowLinkInText = true
                )
            }
        }
    }

    private fun showServiceTokenWarningIfRequired() {
        val token = TokenStore.getToken(viewModel.getTokenSlug())
        if (token?.isLpToken == true ||
            listOf(
                STAKE_SLUG,
                STAKED_MYCOIN_SLUG,
                STAKED_USDE_SLUG
            ).contains(viewModel.getTokenSlug()) ||
            PRICELESS_TOKEN_HASHES.contains(viewModel.inputStateFlow.value.tokenCodeHash)
        )
            showAlert(
                LocaleController.getString("Warning!"),
                LocaleController.getString("\$service_token_transfer_warning"),
                button = LocaleController.getString("Got It"),
                primaryIsDanger = true
            )
    }

    override fun onDestroy() {
        super.onDestroy()
        WalletCore.unregisterObserver(this)
        scrollView.setOnScrollChangeListener(null)
        addressInputView.qrScanImageView.setOnClickListener(null)
        addressInputView.removeTextChangedListener(onInputDestinationTextWatcher)
        amountInputView.tokenSelectorView.setOnClickListener(null)
        amountInputView.doOnEquivalentButtonClick(null)
        amountInputView.doOnFeeButtonClick(null)
        amountInputView.doOnMaxButtonClick(null)
        amountInputView.amountEditText.removeTextChangedListener(onAmountTextWatcher)
        commentInputView.removeTextChangedListener(onInputCommentTextWatcher)
        continueButton.setOnClickListener(null)
    }

    private fun switchTokenBasedOnChain(address: String) {
        val token =
            TokenStore.getToken(viewModel.getTokenSlug())
        if (token?.mBlockchain?.isValidAddress(address) != true) {
            for (blockchain in MBlockchain.supportedChains) {
                if (blockchain.isValidAddress(address)) {
                    viewModel.onInputToken(blockchain.nativeSlug)
                }
            }
        }
    }

    private var sentActivityId: String? = null
    private var receivedLocalActivities: ArrayList<MApiTransaction>? = null
    private fun checkReceivedActivity(receivedActivity: MApiTransaction) {
        if (sentActivityId == null) {
            // Send in-progress, cached received local activity to process on send api callback is called
            if (receivedActivity.isLocal()) {
                if (receivedLocalActivities == null)
                    receivedLocalActivities = ArrayList()
                receivedLocalActivities?.add(receivedActivity)
            }
            return
        }

        val txMatch =
            receivedActivity is MApiTransaction.Transaction && sentActivityId == receivedActivity.getTxHash()
        if (!txMatch) {
            return
        }

        sentActivityId = null
        WalletCore.unregisterObserver(this)
        if (window?.topNavigationController != navigationController) {
            window?.dismissNav(navigationController)
            return
        }
        window?.dismissLastNav {
            WalletCore.notifyEvent(
                WalletEvent.OpenActivity(
                    displayedAccount.accountId!!,
                    receivedActivity
                )
            )
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
