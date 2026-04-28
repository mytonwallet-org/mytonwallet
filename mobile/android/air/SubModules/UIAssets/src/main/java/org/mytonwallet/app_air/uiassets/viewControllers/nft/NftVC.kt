package org.mytonwallet.app_air.uiassets.viewControllers.nft

import android.animation.ValueAnimator
import org.mytonwallet.app_air.uicomponents.helpers.adaptiveFontSize
import android.content.Context
import android.graphics.Color
import android.graphics.drawable.Drawable
import android.os.Handler
import android.os.Looper
import android.text.Layout
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.util.TypedValue.COMPLEX_UNIT_SP
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.animation.AccelerateDecelerateInterpolator
import android.view.animation.AccelerateInterpolator
import android.view.animation.DecelerateInterpolator
import android.widget.FrameLayout
import androidx.appcompat.widget.AppCompatImageButton
import androidx.constraintlayout.widget.ConstraintLayout.LayoutParams
import androidx.core.text.buildSpannedString
import androidx.core.text.inSpans
import androidx.core.view.children
import androidx.core.view.isGone
import androidx.core.view.isVisible
import androidx.core.view.setPadding
import androidx.core.view.updateLayoutParams
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import org.mytonwallet.app_air.uiassets.viewControllers.CollectionsMenuHelpers
import org.mytonwallet.app_air.uiassets.viewControllers.nft.views.NftAttributesView
import org.mytonwallet.app_air.uiassets.viewControllers.nft.views.NftHeaderView
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.commonViews.ReversedCornerView
import org.mytonwallet.app_air.uicomponents.commonViews.cells.HeaderCell
import org.mytonwallet.app_air.uicomponents.drawable.RotatableDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.exactly
import org.mytonwallet.app_air.uicomponents.extensions.resize
import org.mytonwallet.app_air.uicomponents.extensions.setSizeBounds
import org.mytonwallet.app_air.uicomponents.extensions.unspecified
import org.mytonwallet.app_air.uicomponents.helpers.AddressPopupHelpers.Companion.presentMenu
import org.mytonwallet.app_air.uicomponents.helpers.DirectionalTouchHandler
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.palette.ImagePaletteHelpers
import org.mytonwallet.app_air.uicomponents.helpers.spans.WTypefaceSpan
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.uicomponents.viewControllers.preview.PreviewVC
import org.mytonwallet.app_air.uicomponents.widgets.WFrameLayout
import org.mytonwallet.app_air.uicomponents.widgets.WImageButton
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.addRippleEffect
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup.BackgroundStyle
import org.mytonwallet.app_air.uicomponents.widgets.scaleIn
import org.mytonwallet.app_air.uicomponents.widgets.scaleOut
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uisend.sendNft.SendNftVC
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.NftAccentColors
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.WORD_JOIN
import org.mytonwallet.app_air.walletbasecontext.utils.getDrawableCompat
import org.mytonwallet.app_air.walletbasecontext.utils.replaceSpacesWithNbsp
import org.mytonwallet.app_air.walletbasecontext.utils.requireDrawableCompat
import org.mytonwallet.app_air.walletcontext.WalletContextManager
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.utils.AnimUtils.Companion.lerp
import org.mytonwallet.app_air.walletcontext.utils.VerticalImageSpan
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.ApiNft
import org.mytonwallet.app_air.walletcore.moshi.ApiNftMetadata
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.NftStore
import java.lang.ref.WeakReference
import kotlin.math.max

class NftVC(
    context: Context,
    val showingAccountId: String,
    var nft: ApiNft,
    val collectionNFTs: List<ApiNft>,
    private val shouldShowOwner: Boolean = false
) : WViewController(context), NftHeaderView.Delegate, WalletCore.EventObserver {
    override val TAG = "Nft"

    override val displayedAccount =
        DisplayedAccount(showingAccountId, AccountStore.isPushedTemporary)

    override val topBarConfiguration: ReversedCornerView.Config
        get() = super.topBarConfiguration.copy(
            blurRootView = recyclerView
        )
    override val shouldDisplayBottomBar = true
    override val isSwipeBackAllowed: Boolean
        get() {
            return collectionNFTs.size == 1 ||
                headerView.isInCompactState ||
                headerView.isInExpandedState
        }
    override val isEdgeSwipeBackAllowed = true

    companion object {
        const val COLLAPSED_ATTRIBUTES_COUNT = 5
        const val WEAR_ITEM_SIZE = 56
        const val SECONDARY_ITEM_SIZE = 36
        const val SECONDARY_ITEM_SCALE = SECONDARY_ITEM_SIZE / WEAR_ITEM_SIZE.toFloat()
        const val NO_WEAR_TRANSLATION_X = SECONDARY_ITEM_SIZE + 12f
        const val NO_WEAR_SHARE_TRANSLATION_X = (WEAR_ITEM_SIZE + SECONDARY_ITEM_SIZE) / 2f + 12f
    }

    private val headerView: NftHeaderView by lazy {
        object : NftHeaderView(
            context,
            nft,
            collectionNFTs,
            navigationController?.getSystemBars()?.top ?: 0,
            (view.parent as View).width,
            WeakReference(this@NftVC)
        ) {
            override fun dispatchTouchEvent(ev: MotionEvent): Boolean {
                return touchHandler.dispatchTouch(headerView, ev) ?: super.dispatchTouchEvent(ev)
            }
        }
    }

    private val moreButton: WImageButton by lazy {
        val btn = WImageButton(context)
        btn.setPadding(8.dp)
        btn.setOnClickListener {
            presentMoreMenu()
        }
        val moreDrawable = context.getDrawableCompat(
            org.mytonwallet.app_air.icons.R.drawable.ic_more
        )
        btn.setImageDrawable(moreDrawable)
        btn.updateColors(WColor.PrimaryLightText, WColor.BackgroundRipple)
        btn
    }

    private val descriptionTitleLabel = HeaderCell(context).apply {
        configure(
            LocaleController.getString("Description"),
            titleColor = WColor.Tint,
            HeaderCell.TopRounding.NORMAL
        )

    }
    private val descriptionLabel: WLabel by lazy {
        WLabel(context).apply {
            setStyle(adaptiveFontSize(), WFont.Regular)
            setTextColor(WColor.PrimaryText)
            useCustomEmoji = true
        }
    }
    private val descriptionView: WView by lazy {
        WView(context).apply {
            addView(descriptionTitleLabel)
            addView(
                descriptionLabel,
                LayoutParams(MATCH_PARENT, WRAP_CONTENT)
            )
            setConstraints {
                toTop(descriptionTitleLabel)
                toStart(descriptionTitleLabel)
                toTop(descriptionLabel, 48f)
                toCenterX(descriptionLabel, 20f)
                toBottom(descriptionLabel, 16f)
            }
        }
    }

    private val isOwnNft: Boolean
        get() {
            if (AccountStore.activeAccount?.accountType == MAccount.AccountType.VIEW) return false
            val ownerAddress = nft.ownerAddress ?: return false
            if (ownerAddress.isEmpty()) return false
            return AccountStore.activeAccount?.addressByChain?.get(nft.chain?.name) == ownerAddress
        }

    private val shouldShowOwnerSection: Boolean
        get() = shouldShowOwner && !nft.ownerAddress.isNullOrEmpty()

    private val ownerTitleLabel = HeaderCell(context).apply {
        configure(
            LocaleController.getString("Owner"),
            titleColor = WColor.Tint,
            HeaderCell.TopRounding.NORMAL
        )
    }
    private val ownerAddressLabel: WLabel by lazy {
        WLabel(context).apply {
            setStyle(adaptiveFontSize(), WFont.Regular)
            setTextColor(WColor.SecondaryText)
            setLineHeight(COMPLEX_UNIT_SP, 24f)
            letterSpacing = -0.015f
            breakStrategy = Layout.BREAK_STRATEGY_SIMPLE
            hyphenationFrequency = Layout.HYPHENATION_FREQUENCY_NONE
            setPadding(0, 0, 0, 16.dp)
            setOnClickListener { v ->
                val container = (v.parent as? View) ?: v
                nft.ownerAddress?.let { onOwnerAddressClicked(container, it) }
            }
        }
    }

    private val ownerView: WView by lazy {
        WView(context).apply {
            addView(ownerTitleLabel)
            addView(
                ownerAddressLabel,
                LayoutParams(0, WRAP_CONTENT)
            )
            setConstraints {
                toTop(ownerTitleLabel)
                toStart(ownerTitleLabel)
                toStart(ownerAddressLabel, 20f)
                toEnd(ownerAddressLabel, 20f)
                topToBottom(ownerAddressLabel, ownerTitleLabel, 8f)
                toBottom(ownerAddressLabel)
            }
        }
    }

    private fun updateOwnerAddress() {
        val address = nft.ownerAddress ?: return
        ownerAddressLabel.text = buildOwnerAddressText(address)
    }

    private fun ownerChainIconDrawable(): Drawable? {
        return nft.chain?.symbolIconPadded?.let {
            context.getDrawableCompat(it)
        }?.mutate()
    }

    private fun buildOwnerAddressText(address: String): CharSequence {
        val chainIconDrawable = ownerChainIconDrawable()?.apply {
            setTint(WColor.SecondaryText.color)
            setSizeBounds(16.dp, 16.dp)
        }

        val expandDrawable = context.getDrawableCompat(
            org.mytonwallet.app_air.icons.R.drawable.ic_arrows_14
        )?.mutate()?.apply {
            setTint(WColor.SecondaryText.color)
            alpha = 204
            setSizeBounds(7.dp, 14.dp)
        }

        val first = address.take(6)
        val last = address.takeLast(6)
        val middle = address.substring(6, address.length - 6)

        return buildSpannedString {
            if (chainIconDrawable != null) {
                inSpans(
                    VerticalImageSpan(
                        chainIconDrawable,
                        endPadding = 2.dp,
                        verticalAlignment = VerticalImageSpan.VerticalAlignment.TOP_BOTTOM
                    )
                ) { append(" ") }
                append(WORD_JOIN)
            }

            inSpans(WTypefaceSpan(WFont.Medium, WColor.PrimaryText)) { append(first) }
            append(middle)
            inSpans(WTypefaceSpan(WFont.Medium, WColor.PrimaryText)) { append(last) }

            if (expandDrawable != null) {
                append(WORD_JOIN)
                inSpans(
                    VerticalImageSpan(
                        expandDrawable,
                        startPadding = 4.5f.dp.toInt(),
                        verticalAlignment = VerticalImageSpan.VerticalAlignment.TOP_BOTTOM
                    )
                ) { append(" ") }
            }
        }.replaceSpacesWithNbsp()
    }


    private fun onOwnerAddressClicked(anchorView: View, address: String) {
        val account = AccountStore.activeAccount ?: return
        presentMenu(
            viewController = WeakReference(this),
            view = anchorView,
            title = null,
            blockchain = MBlockchain.ton,
            network = account.network,
            address = address,
            centerHorizontally = true,
            showTemporaryViewOption = true,
            windowBackgroundStyle = BackgroundStyle.Cutout.fromView(
                anchorView,
                roundRadius = ViewConstants.BLOCK_RADIUS.dp
            )
        ) { displayProgress ->
            actionsView.alpha = 1f - displayProgress
        }
    }


    private val attributesTitleLabel = HeaderCell(context).apply {
        configure(
            LocaleController.getString("Attributes"),
            titleColor = WColor.Tint,
            HeaderCell.TopRounding.NORMAL
        )
    }
    private val attributesContentView = NftAttributesView(context)
    private val attributesToggleLabel by lazy {
        WLabel(context).apply {
            setStyle(15f, WFont.Medium)
            setTextColor(WColor.Tint)
            isTinted = true
        }
    }
    private var arrowDrawable: RotatableDrawable? = null
    private var isAttributesSectionExpanded = false
    private var attributesAnimator: ValueAnimator? = null
    private val attributesToggleView: WFrameLayout by lazy {
        WFrameLayout(context).apply {
            addView(
                attributesToggleLabel,
                FrameLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
                    gravity = Gravity.START or Gravity.CENTER_VERTICAL
                    marginStart = 24.dp
                    bottomMargin = 2.dp
                })
            setOnClickListener {
                isAttributesSectionExpanded = !isAttributesSectionExpanded
                attributesAnimator?.cancel()
                attributesAnimator = ValueAnimator.ofInt(
                    attributesContentView.height,
                    if (isAttributesSectionExpanded) attributesContentView.fullHeight else attributesContentView.collapsedHeight
                ).apply {
                    duration = AnimationConstants.QUICK_ANIMATION
                    interpolator = AccelerateDecelerateInterpolator()
                    addUpdateListener { animation ->
                        val animatedValue = animation.animatedValue as Int
                        val layoutParams = attributesContentView.layoutParams
                        layoutParams.height = animatedValue
                        attributesContentView.layoutParams = layoutParams
                        updatePadding(overrideAttributesContentHeight = animatedValue)
                        arrowDrawable?.rotation =
                            (if (isAttributesSectionExpanded) animation.animatedFraction else (1 + animation.animatedFraction)) * 180
                        attributesToggleLabel.invalidate()
                    }
                    start()
                    updateToggleText()
                }
            }
        }
    }
    private val nftAttributes: List<ApiNftMetadata.Attribute>
        get() = nft.metadata?.attributes?.filterNotNull() ?: emptyList()
    private val isAttributesSectionExpandable: Boolean
        get() {
            return nftAttributes.size > COLLAPSED_ATTRIBUTES_COUNT
        }
    private val attributesView: WView by lazy {
        WView(context).apply {
            addView(attributesTitleLabel)
            addView(attributesContentView, LayoutParams(MATCH_PARENT, WRAP_CONTENT))
            addView(attributesToggleView, LayoutParams(MATCH_PARENT, 42.dp))
            setConstraints {
                toTop(attributesTitleLabel)
                toStart(attributesTitleLabel)
                toCenterX(attributesContentView, 16f)
                toTop(attributesContentView, 48f)
            }
        }
    }

    private val wearActionButton: AppCompatImageButton by lazy {
        AppCompatImageButton(context).apply {
            id = View.generateViewId()
            elevation = 8f.dp
            setOnClickListener {
                presentWearMenu()
            }
        }
    }
    private val shareActionButton: AppCompatImageButton by lazy {
        AppCompatImageButton(context).apply {
            id = View.generateViewId()
            elevation = 8f.dp
            scaleX = if (isShowingWearButton) {
                SECONDARY_ITEM_SCALE
            } else {
                1f
            }
            scaleY = scaleX
            setOnClickListener {
                navigationController?.let {
                    CollectionsMenuHelpers.shareNft(showingAccountId, nft, it)
                }
            }
        }
    }
    private val sendActionButton: AppCompatImageButton by lazy {
        AppCompatImageButton(context).apply {
            id = View.generateViewId()
            elevation = 5.14f.dp
            setOnClickListener {
                push(SendNftVC(context, nft))
            }
            isVisible = isOwnNft
        }
    }
    private val actionsView: WView by lazy {
        WView(context).apply {
            addView(wearActionButton, LayoutParams(WEAR_ITEM_SIZE.dp, WEAR_ITEM_SIZE.dp))
            addView(shareActionButton, LayoutParams(WEAR_ITEM_SIZE.dp, WEAR_ITEM_SIZE.dp))
            addView(sendActionButton, LayoutParams(SECONDARY_ITEM_SIZE.dp, SECONDARY_ITEM_SIZE.dp))
            setConstraints {
                toStart(sendActionButton, 4f)
                toCenterY(sendActionButton)
                toEnd(sendActionButton, WEAR_ITEM_SIZE + SECONDARY_ITEM_SIZE + 42f)
                toCenterY(shareActionButton)
                toEnd(shareActionButton, WEAR_ITEM_SIZE + 20f)
                toCenterY(wearActionButton)
                toEnd(wearActionButton, 18f)
            }
        }
    }

    private val scrollingContentView: WView by lazy {
        val v = WView(context, LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        v.setPadding(
            0,
            NftHeaderView.OVERSCROLL_OFFSET.dp + (view.parent as View).width,
            0,
            (navigationController?.getSystemBars()?.bottom ?: 0)
        )
        v.addView(ownerView, LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        v.setConstraints { toCenterX(ownerView, ViewConstants.HORIZONTAL_PADDINGS.toFloat()) }

        v.addView(descriptionView, LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        v.setConstraints { toCenterX(descriptionView, ViewConstants.HORIZONTAL_PADDINGS.toFloat()) }

        v.addView(attributesView, LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        v.setConstraints {
            toBottom(attributesView)
            toCenterX(attributesView, ViewConstants.HORIZONTAL_PADDINGS.toFloat())
        }
        v
    }

    private class SingleViewAdapter(val scrollingContentView: View) :
        RecyclerView.Adapter<SingleViewAdapter.ViewHolder>() {

        class ViewHolder(itemView: View) : RecyclerView.ViewHolder(itemView)

        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ViewHolder {
            return ViewHolder(scrollingContentView)
        }

        override fun onBindViewHolder(holder: ViewHolder, position: Int) {
        }

        override fun getItemCount(): Int = 1
    }

    private var wasTracking = false
    private var scrollListener = object : RecyclerView.OnScrollListener() {
        override fun onScrolled(recyclerView: RecyclerView, dx: Int, dy: Int) {
            super.onScrolled(recyclerView, dx, dy)
            val scrollOffset = recyclerView.computeVerticalScrollOffset()
            if (!wasTracking && shouldLimitFling && scrollOffset < headerView.collapsedOffset) {
                recyclerView.scrollBy(0, headerView.collapsedOffset - scrollOffset)
                return
            }
            headerView.update(scrollOffset)
            updateActionsPosition(scrollOffset)
            headerView
        }

        override fun onScrollStateChanged(recyclerView: RecyclerView, newState: Int) {
            super.onScrollStateChanged(recyclerView, newState)
            headerView.isTracking = newState != RecyclerView.SCROLL_STATE_IDLE
            if (wasTracking && (
                    newState == RecyclerView.SCROLL_STATE_IDLE ||
                        newState == RecyclerView.SCROLL_STATE_SETTLING
                    )
            ) {
                wasTracking = false
                if (newState == RecyclerView.SCROLL_STATE_SETTLING) {
                    recyclerView.scrollBy(0, 0)
                    recyclerView.post {
                        shouldLimitFling = !adjustScrollPosition()
                    }
                } else {
                    shouldLimitFling = false
                    adjustScrollPosition()
                }
            } else if (newState == RecyclerView.SCROLL_STATE_DRAGGING) {
                shouldLimitFling = false
                wasTracking = true
            }
        }
    }

    private val touchHandler by lazy {
        DirectionalTouchHandler(
            verticalView = recyclerView,
            horizontalView = headerView.avatarCoverFlowView,
            interceptedViews = listOf(headerView.avatarImageView),
            interceptedByVerticalScrollViews = listOf(headerView.avatarCoverFlowView),
            isDirectionalScrollAllowed = { isVertical, _ ->
                !isVertical || (!nft.description.isNullOrEmpty() || shouldShowOwnerSection || nftAttributes.isNotEmpty())
            })
    }

    private var shouldLimitFling = false
    private val recyclerView: RecyclerView by lazy {
        object : RecyclerView(context) {
            override fun dispatchTouchEvent(ev: MotionEvent): Boolean {
                return touchHandler.dispatchTouch(recyclerView, ev) ?: super.dispatchTouchEvent(ev)
            }
        }.apply {
            id = View.generateViewId()
            adapter = SingleViewAdapter(scrollingContentView)
            layoutManager = LinearLayoutManager(context, LinearLayoutManager.VERTICAL, false)
            overScrollMode = View.OVER_SCROLL_NEVER
        }
    }

    override fun setupViews() {
        super.setupViews()

        WalletCore.registerObserver(this)
        setupNavBar(true)
        navigationBar?.addTrailingView(moreButton, LayoutParams(40.dp, 40.dp))
        view.addView(recyclerView, LayoutParams(MATCH_PARENT, MATCH_PARENT))
        view.addView(headerView, LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        view.addView(actionsView, LayoutParams(WRAP_CONTENT, 100.dp))
        view.setConstraints {
            allEdges(recyclerView)
            toTop(headerView)
            toTop(actionsView)
            toEnd(actionsView, ViewConstants.HORIZONTAL_PADDINGS.toFloat())
        }

        setupNft(isChanged = false)
        updateTheme()
    }

    private fun updateAttributes() {
        attributesView.isGone = nftAttributes.isEmpty()
        if (!attributesView.isVisible)
            return
        attributesContentView.setupNft(nft)
        attributesToggleView.isGone = !isAttributesSectionExpandable
        attributesView.setConstraints {
            if (isAttributesSectionExpandable) {
                toBottom(attributesContentView, 46f)
                toBottom(attributesToggleView)
            } else {
                toBottom(attributesContentView, 16f)
            }
        }
    }

    private var isShowingWearButton = nft.isMtwCard
    private fun setupNft(isChanged: Boolean) {
        ownerView.isGone = !shouldShowOwnerSection
        if (ownerView.isVisible) {
            updateOwnerAddress()
        }

        descriptionLabel.text = nft.description
        descriptionView.isGone = nft.description.isNullOrEmpty()

        updateAttributes()

        scrollingContentView.setConstraints {
            if (ownerView.isVisible) {
                toTop(ownerView)
            }
            if (descriptionView.isVisible) {
                if (ownerView.isVisible) {
                    topToBottom(descriptionView, ownerView, 16f)
                } else {
                    toTop(descriptionView)
                }
            }
            val previousView = when {
                descriptionView.isVisible -> descriptionView
                ownerView.isVisible -> ownerView
                else -> null
            }
            if (previousView == null) {
                toTop(attributesView)
            } else {
                topToBottom(attributesView, previousView, 16f)
            }
        }
        // Add enough bottom padding to prevent recycler-view scroll before calculating and setting the correct padding
        scrollingContentView.setPadding(0, scrollingContentView.paddingTop, 0, view.height)
        attributesContentView.measure(
            (scrollingContentView.width - 32.dp).exactly,
            0.unspecified
        )
        if (isAttributesSectionExpandable) {
            attributesContentView.updateLayoutParams {
                height = attributesContentView.collapsedHeight
            }
            attributesContentView.post {
                updatePadding()
            }
        } else {
            attributesContentView.updateLayoutParams {
                height = attributesContentView.fullHeight
            }
        }
        view.post {
            insetsUpdated()
        }
        updateSendActionState()
        updateSectionsBackground(currentVal)
        // Update theme and animate actions
        if (isChanged) {
            val hadWearBefore = isShowingWearButton
            isShowingWearButton = nft.isMtwCard
            if (isShowingWearButton) {
                updateWearButtonTheme()
            }
            val hidingWearButton = hadWearBefore && !nft.isMtwCard
            val showingWearButton = !hadWearBefore && nft.isMtwCard
            val startSendTransactionX = sendActionButton.translationX
            val startShareTransactionX = shareActionButton.translationX
            val startShareScale = shareActionButton.scaleX
            if (hidingWearButton || showingWearButton) {
                ValueAnimator.ofFloat(0f, 1f).apply {
                    duration = AnimationConstants.VERY_QUICK_ANIMATION
                    interpolator = AccelerateDecelerateInterpolator()
                    addUpdateListener { animation ->
                        if (hidingWearButton) {
                            sendActionButton.translationX =
                                lerp(
                                    startSendTransactionX,
                                    NO_WEAR_TRANSLATION_X.dp,
                                    animation.animatedFraction
                                ) * LocaleController.rtlMultiplier
                            shareActionButton.translationX =
                                lerp(
                                    startShareTransactionX,
                                    NO_WEAR_SHARE_TRANSLATION_X.dp,
                                    animation.animatedFraction
                                ) * LocaleController.rtlMultiplier
                            shareActionButton.scaleX =
                                lerp(startShareScale, 1f, animatedFraction)
                            wearActionButton.scaleX = 1 - animatedFraction
                        } else {
                            sendActionButton.translationX =
                                lerp(
                                    startSendTransactionX,
                                    0f.dp,
                                    animation.animatedFraction
                                )
                            shareActionButton.translationX =
                                lerp(
                                    startShareTransactionX,
                                    0f.dp,
                                    animation.animatedFraction
                                )
                            shareActionButton.scaleX =
                                lerp(startShareScale, SECONDARY_ITEM_SCALE, animatedFraction)
                            wearActionButton.scaleX = animatedFraction
                        }
                        shareActionButton.scaleY = shareActionButton.scaleX
                        wearActionButton.scaleY = wearActionButton.scaleX
                    }
                    start()
                }
            }
            updateAttributesTheme()
        } else {
            if (isShowingWearButton) {
                updateWearButtonTheme()
                sendActionButton.translationX = 0f
                shareActionButton.translationX = 0f
                wearActionButton.scaleX = 1f
            } else {
                sendActionButton.translationX =
                    NO_WEAR_TRANSLATION_X.dp * LocaleController.rtlMultiplier
                shareActionButton.translationX =
                    NO_WEAR_SHARE_TRANSLATION_X.dp * LocaleController.rtlMultiplier
                wearActionButton.scaleX = 0f
            }
            wearActionButton.scaleY = shareActionButton.scaleX
        }
    }

    override fun scrollToTop() {
        super.scrollToTop()
        if (wasTracking || !headerView.targetIsCollapsed)
            return
        performScrollToTop()
    }

    private fun performScrollToTop() {
        recyclerView.smoothScrollBy(
            0,
            headerView.collapsedOffset - recyclerView.computeVerticalScrollOffset(),
            AccelerateDecelerateInterpolator(),
            AnimationConstants.VERY_QUICK_ANIMATION.toInt()
        )
    }

    override fun didSetupViews() {
        super.didSetupViews()
        headerView.bringToFront()
        actionsView.bringToFront()
    }

    override fun viewWillAppear() {
        super.viewWillAppear()
        window?.forceStatusBarLight = if (!headerView.targetIsCollapsed) true else null
    }

    override fun viewWillDisappear() {
        super.viewWillDisappear()
        window?.forceStatusBarLight = null
    }

    override fun onDestroy() {
        WalletCore.unregisterObserver(this)
        super.onDestroy()
        headerView.onDestroy()
    }

    override fun onWalletEvent(walletEvent: WalletEvent) {
        when (walletEvent) {
            WalletEvent.NftsUpdated,
            WalletEvent.ReceivedNewNFT -> {
                reloadNftFromStore()
            }

            else -> {}
        }
    }

    var insetsUpdatedOnce = false
    override fun insetsUpdated() {
        super.insetsUpdated()
        view.post {
            updatePadding(
                if (!insetsUpdatedOnce && isAttributesSectionExpandable)
                    (98.dp + if (isAttributesSectionExpanded) {
                        attributesContentView.fullHeight
                    } else {
                        attributesContentView.collapsedHeight
                    })
                else null
            )
            if (!insetsUpdatedOnce) {
                val scrollOffset = headerView.expandPercentToOffset(0f)
                recyclerView.post {
                    recyclerView.addOnScrollListener(scrollListener)
                    recyclerView.scrollBy(0, scrollOffset)
                    updateActionsPosition(scrollOffset)
                }
            }
            insetsUpdatedOnce = true
        }
    }

    private fun updatePadding(overrideAttributesContentHeight: Int? = null) {
        val attributesHeight = overrideAttributesContentHeight?.let {
            98.dp + overrideAttributesContentHeight
        } ?: attributesView.height

        val spacing = 16.dp
        val ownerHeight = if (ownerView.isVisible) ownerView.height else 0
        val descriptionHeight = if (descriptionView.isVisible) descriptionView.height else 0
        val attributesSectionHeight = if (attributesView.isVisible) attributesHeight else 0

        val contentHeight =
            ownerHeight +
                (if (ownerHeight > 0 && descriptionHeight > 0) spacing else 0) +
                descriptionHeight +
                (if ((ownerHeight > 0 || descriptionHeight > 0) && attributesSectionHeight > 0) spacing else 0) +
                attributesSectionHeight

        if (view.parent != null)
            scrollingContentView.setPadding(
                0,
                NftHeaderView.OVERSCROLL_OFFSET.dp + (view.parent as View).width,
                0,
                navigationController!!.getSystemBars().bottom.coerceAtLeast(
                    view.height -
                        (
                            contentHeight +
                                navigationController!!.getSystemBars().top +
                                WNavigationBar.DEFAULT_HEIGHT.dp
                            )
                )
            )
    }

    private fun updateSectionsBackground(topRadius: Float) {
        val fullRadius = ViewConstants.BLOCK_RADIUS.dp
        val topView = when {
            ownerView.isVisible -> ownerView
            descriptionView.isVisible -> descriptionView
            attributesView.isVisible -> attributesView
            else -> null
        }

        if (ownerView.isVisible)
            ownerView.setBackgroundColor(
                WColor.Background.color,
                if (topView === ownerView) topRadius else fullRadius,
                fullRadius
            )

        if (descriptionView.isVisible)
            descriptionView.setBackgroundColor(
                WColor.Background.color,
                if (topView === descriptionView) topRadius else fullRadius,
                fullRadius
            )

        if (attributesView.isVisible)
            attributesView.setBackgroundColor(
                WColor.Background.color,
                if (topView === attributesView) topRadius else fullRadius,
                fullRadius
            )
    }


    override val isTinted = true
    override fun updateTheme() {
        super.updateTheme()

        recyclerView.setBackgroundColor(WColor.SecondaryBackground.color)
        currentVal = if (headerView.targetIsCollapsed) ViewConstants.BLOCK_RADIUS.dp else 0f
        updateSectionsBackground(currentVal)
        navigationBar?.setTint(
            if (headerView.targetIsCollapsed) WColor.PrimaryLightText else WColor.White,
            animated = false
        )
        sendActionButton.setImageDrawable(
            context.requireDrawableCompat(
                org.mytonwallet.app_air.uiassets.R.drawable.ic_nft_send
            ).apply {
                setTint(WColor.PrimaryLightText.color)
            }
        )
        sendActionButton.setBackgroundColor(WColor.Background.color, 28f.dp)
        sendActionButton.addRippleEffect(WColor.BackgroundRipple.color, 28f.dp)

        updateShareActionTheme()
        shareActionButton.setBackgroundColor(WColor.Background.color, 28f.dp)
        shareActionButton.addRippleEffect(WColor.BackgroundRipple.color, 28f.dp)
        if (nft.isMtwCard) {
            updateWearButtonTheme()
        }
        updateAttributesTheme()
    }

    private fun updateSendActionState() {
        if (isOwnNft && !nft.isOnSale) {
            sendActionButton.isEnabled = true
            sendActionButton.scaleIn(AnimationConstants.SUPER_QUICK_ANIMATION)
        } else {
            sendActionButton.isEnabled = false
            sendActionButton.scaleOut(AnimationConstants.SUPER_QUICK_ANIMATION)
        }
    }

    private fun reloadNftFromStore() {
        val updatedNft = NftStore.nftData?.cachedNfts?.firstOrNull {
            it.address == nft.address
        } ?: return
        if (updatedNft == nft) {
            return
        }

        nft = updatedNft
        headerView.nft = updatedNft
        headerView.configNft()
        setupNft(isChanged = true)
    }

    private fun updateShareActionTheme() {
        val drawable = context.getDrawableCompat(
            org.mytonwallet.app_air.uiassets.R.drawable.ic_nft_share
        )?.mutate()
        drawable?.setTint(WColor.PrimaryLightText.color)
        if (!nft.isMtwCard && drawable != null) {
            shareActionButton.setImageDrawable(drawable.resize(context, 34.dp, 34.dp))
        } else {
            shareActionButton.setImageDrawable(drawable)
        }
    }

    private fun updateWearButtonTheme() {
        wearActionButton.setImageDrawable(
            context.requireDrawableCompat(
                org.mytonwallet.app_air.uiassets.R.drawable.ic_nft_wear
            ).apply {
                setTint(
                    if (!NftAccentColors.veryBrightColors.contains(WColor.Tint.color))
                        Color.WHITE
                    else
                        Color.BLACK
                )
            }
        )
        wearActionButton.setBackgroundColor(WColor.Tint.color, 28f.dp)
        wearActionButton.addRippleEffect(WColor.TintRipple.color, 28f.dp)
    }

    private fun updateAttributesTheme() {
        if (isAttributesSectionExpandable) {
            if (arrowDrawable == null) {
                arrowDrawable = RotatableDrawable(
                    context.requireDrawableCompat(
                        org.mytonwallet.app_air.icons.R.drawable.ic_arrow_bottom_14
                    ).apply {
                        mutate()
                        setTint(WColor.Tint.color)
                    }
                )
            } else {
                arrowDrawable?.setTint(WColor.Tint.color)
            }
            updateToggleText()
        }
    }

    private fun adjustScrollPosition(): Boolean {
        val canGoDown = recyclerView.canScrollVertically(1)
        if (!canGoDown)
            return false
        headerView.nearestScrollPosition()?.let {
            val currentOffset = recyclerView.computeVerticalScrollOffset()
            if (currentOffset != it)
                recyclerView.smoothScrollBy(
                    0,
                    it - recyclerView.computeVerticalScrollOffset()
                )
            return true
        } ?: return false
    }

    private var currentVal = ViewConstants.BLOCK_RADIUS.dp
    private fun animateDescriptionRadius(newVal: Float) {
        val prevVal = currentVal
        currentVal = newVal
        ValueAnimator.ofFloat(prevVal, newVal).apply {
            setDuration(AnimationConstants.QUICK_ANIMATION)
            interpolator = AccelerateDecelerateInterpolator()
            addUpdateListener { animation ->
                updateSectionsBackground(animation.animatedValue as Float)
            }
            start()
        }
    }

    private fun updateActionsPosition(scrollOffset: Int) {
        actionsView.translationY =
            max(
                navigationController!!.getSystemBars().top + WNavigationBar.DEFAULT_HEIGHT.dp,
                recyclerView.width - scrollOffset + NftHeaderView.OVERSCROLL_OFFSET.dp
            ) - 50f.dp
    }


    private fun updateToggleText() {
        val txt =
            LocaleController.getString(if (isAttributesSectionExpanded) "Collapse" else "Show All")
        val ss = SpannableStringBuilder(txt)
        val imageSpan = VerticalImageSpan(arrowDrawable as Drawable, 3.dp, 3.dp)
        ss.append(" ", imageSpan, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        attributesToggleLabel.text = ss
        attributesToggleView.background = null
        attributesToggleView.addRippleEffect(WColor.TintRipple.color, 0f)
    }

    override fun onNftChanged(nft: ApiNft) {
        this.nft = nft
        setupNft(isChanged = true)
    }

    override fun onExpandTapped() {
        if (wasTracking)
            return
        if (headerView.targetIsCollapsed) {
            headerView.isAnimatingImageToExpand = true
            recyclerView.smoothScrollBy(
                0,
                NftHeaderView.OVERSCROLL_OFFSET.dp - recyclerView.computeVerticalScrollOffset(),
                AccelerateDecelerateInterpolator(),
                AnimationConstants.QUICK_ANIMATION.toInt()
            )
        } else {
            onPreviewTapped()
        }
    }

    override fun onBackPressed(): Boolean {
        if (!headerView.targetIsCollapsed) {
            performScrollToTop()
            return false
        }
        return super.onBackPressed()
    }

    override fun onPreviewTapped() {
        val image = nft.image ?: return
        touchHandler.stopScroll()
        view.lockView()
        val previewVC = PreviewVC(
            context,
            if (nft.metadata?.lottie.isNullOrEmpty()) null else headerView.animationView,
            Content.ofUrl(image),
            headerView.avatarPosition,
            headerView.avatarCornerRadius.dp,
            onPreviewDismissed = {
                view.unlockView()
                headerView.onPreviewEnded()
                if (!headerView.targetIsCollapsed) {
                    navigationBar?.fadeInActions()
                    headerView.showLabels()
                    showActions()
                }
            }
        )
        val nav = WNavigationController(
            window!!, WNavigationController.PresentationConfig(
                overFullScreen = false
            )
        )
        nav.setRoot(previewVC)
        window?.present(nav, animated = false)
        fun startTransition() {
            headerView.removeView(headerView.animationView)
            previewVC.startTransition()
            previewVC.view.post {
                headerView.onPreviewStarted()
            }
        }
        if (headerView.targetIsCollapsed) {
            startTransition()
        } else {
            navigationBar?.fadeOutActions()
            headerView.hideLabels()
            hideActions()
            Handler(Looper.getMainLooper()).postDelayed({
                startTransition()
            }, AnimationConstants.QUICK_ANIMATION)
        }
    }

    override fun onCollectionTapped() {
        navigationController?.let {
            CollectionsMenuHelpers.openCollection(showingAccountId, nft, it)
        }
    }

    override fun onHeaderExpanded() {
        window?.forceStatusBarLight = true
        animateDescriptionRadius(0f)
        navigationBar?.setTint(WColor.White, animated = true)
    }

    override fun onHeaderCollapsed() {
        window?.forceStatusBarLight = null
        animateDescriptionRadius(ViewConstants.BLOCK_RADIUS.dp)
        navigationBar?.setTint(WColor.PrimaryLightText, animated = true)
    }

    override fun showActions() {
        actionsView.children.forEachIndexed { index, child ->
            child.clearAnimation()
            val scaleX = when (child) {
                shareActionButton -> {
                    if (isShowingWearButton) SECONDARY_ITEM_SCALE else 1f
                }

                wearActionButton -> {
                    if (isShowingWearButton) 1f else 0f
                }

                else -> {
                    1f
                }
            }
            child.animate()
                .scaleX(scaleX)
                .scaleY(scaleX)
                .setDuration(AnimationConstants.VERY_QUICK_ANIMATION)
                .setStartDelay(index * 50L)
                .setInterpolator(DecelerateInterpolator())
                .start()
        }
    }

    override fun hideActions() {
        actionsView.children.forEachIndexed { index, child ->
            child.clearAnimation()
            child.animate()
                .scaleX(0f)
                .scaleY(0f)
                .setDuration(AnimationConstants.VERY_QUICK_ANIMATION)
                .setStartDelay((actionsView.children.toList().size - index - 1) * 30L)
                .setInterpolator(AccelerateInterpolator())
                .start()
        }
    }

    private fun presentMoreMenu() {
        WMenuPopup.present(
            moreButton,
            mutableListOf<WMenuPopup.Item>().apply {
                addAll(CollectionsMenuHelpers.buildNftOpenInItems(showingAccountId, nft))
                if (this.isNotEmpty()) {
                    this.last().hasSeparator = true
                }
                if (nft.canRenew() && isOwnNft && !nft.isOnSale) {
                    add(
                        WMenuPopup.Item(
                            org.mytonwallet.app_air.uiassets.R.drawable.ic_renew,
                            LocaleController.getString("Renew"),
                            false,
                        ) {
                            navigationController?.let {
                                CollectionsMenuHelpers.presentRenewModal(it, nft)
                            }
                        }
                    )
                }
                if (nft.canLinkToAddress() && isOwnNft && !nft.isOnSale) {
                    val linkedAddress = NftStore.nftData?.linkedAddressByAddress?.get(nft.address)
                    add(
                        WMenuPopup.Item(
                            org.mytonwallet.app_air.uiassets.R.drawable.ic_link,
                            LocaleController.getString(
                                if (linkedAddress.isNullOrBlank()) "Link to Wallet" else "Change Wallet"
                            ),
                            false,
                        ) {
                            navigationController?.let {
                                CollectionsMenuHelpers.presentLinkToWalletModal(it, nft)
                            }
                        }
                    )
                }

                if (nft.shouldHide()) {
                    add(
                        WMenuPopup.Item(
                            org.mytonwallet.app_air.uiassets.R.drawable.ic_nft_unhide,
                            LocaleController.getString("Unhide"),
                            false,
                        ) {
                            CollectionsMenuHelpers.toggleNftVisibility(nft)
                        }
                    )
                } else {
                    add(
                        WMenuPopup.Item(
                            org.mytonwallet.app_air.uiassets.R.drawable.ic_nft_hide,
                            LocaleController.getString("Hide"),
                            false,
                        ) {
                            CollectionsMenuHelpers.toggleNftVisibility(nft)
                        }
                    )
                }
                if (isOwnNft && !nft.isOnSale) {
                    add(
                        WMenuPopup.Item(
                            WMenuPopup.Item.Config.Item(
                                icon = WMenuPopup.Item.Config.Icon(
                                    icon = org.mytonwallet.app_air.uiassets.R.drawable.ic_burn,
                                    tintColor = null,
                                    iconSize = 28.dp
                                ),
                                title = LocaleController.getString("\$burn_action"),
                                titleColor = WColor.Red.color
                            ),
                            false,
                        ) {
                            navigationController?.let {
                                CollectionsMenuHelpers.pushBurnNftConfirm(it, nft)
                            }
                        }
                    )
                }
            },
            popupWidth = WRAP_CONTENT,
            positioning = WMenuPopup.Positioning.ALIGNED,
            backdropStyle = WMenuPopup.BackdropStyle.Transparent
        )
    }

    private fun presentWearMenu() {
        WMenuPopup.present(
            wearActionButton,
            mutableListOf(
                WMenuPopup.Item(
                    WMenuPopup.Item.Config.Item(
                        icon = WMenuPopup.Item.Config.Icon(
                            icon = org.mytonwallet.app_air.uiassets.R.drawable.ic_card_install,
                            tintColor = null,
                            iconSize = 28.dp
                        ),
                        title = LocaleController.getString(
                            if (nft.isInstalledMtwCard)
                                "Reset Card"
                            else
                                "Install Card"
                        ),
                    ),
                    false,
                ) {
                    if (nft.isInstalledMtwCard) {
                        WGlobalStorage.setCardBackgroundNft(
                            showingAccountId,
                            null
                        )
                        resetPalette()
                    } else {
                        WGlobalStorage.setCardBackgroundNft(
                            showingAccountId,
                            nft.toDictionary()
                        )
                        if (!nft.isInstalledMtwCardPalette) {
                            installPalette()
                        }
                    }
                    WalletCore.notifyEvent(WalletEvent.NftCardUpdated)
                },
                WMenuPopup.Item(
                    WMenuPopup.Item.Config.Item(
                        icon = WMenuPopup.Item.Config.Icon(
                            icon = org.mytonwallet.app_air.uiassets.R.drawable.ic_card_pallete,
                            tintColor = null,
                            iconSize = 28.dp
                        ),
                        title = LocaleController.getString(
                            if (nft.isInstalledMtwCardPalette)
                                "Reset Palette"
                            else
                                "Install Palette"
                        )
                    ),
                    false,
                ) {
                    if (nft.isInstalledMtwCardPalette) {
                        resetPalette()
                    } else {
                        installPalette()
                    }
                },
            ),
            yOffset = 2.dp,
            popupWidth = WRAP_CONTENT,
            positioning = WMenuPopup.Positioning.BELOW,
            windowBackgroundStyle = BackgroundStyle.Cutout.fromView(
                wearActionButton,
                roundRadius = WEAR_ITEM_SIZE.dp.toFloat()
            )
        )
    }

    private var isInstallingPaletteColor = false
    private fun installPalette() {
        if (isInstallingPaletteColor)
            return
        isInstallingPaletteColor = true
        ImagePaletteHelpers.extractPaletteFromNft(
            nft
        ) { colorIndex ->
            isInstallingPaletteColor = false
            if (colorIndex != null) {
                WGlobalStorage.setNftAccentColor(
                    showingAccountId,
                    colorIndex,
                    nft.toDictionary()
                )
            }
            WalletContextManager.delegate?.themeChanged()
        }
    }

    private fun resetPalette() {
        WGlobalStorage.setNftAccentColor(
            showingAccountId,
            null,
            null
        )
        WalletContextManager.delegate?.themeChanged()
    }

}
