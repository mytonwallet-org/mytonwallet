package org.mytonwallet.app_air.uicomponents.base

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.graphics.drawable.Drawable
import android.text.TextUtils
import android.view.Gravity
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.FrameLayout
import android.widget.LinearLayout
import androidx.core.view.doOnPreDraw
import androidx.core.view.isVisible
import androidx.core.view.setPadding
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.extensions.animateTintColor
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WImageButton
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.addRippleEffect
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.helpers.WInterpolator

@SuppressLint("ViewConstructor")
class WActionBar(
    context: Context,
    defaultHeight: Int = DEFAULT_HEIGHT,
    private val contentMarginTop: Int = 0
) : WView(context), WThemedView {

    companion object {
        const val DEFAULT_HEIGHT = 64

        private const val ACTION_BUTTON_SIZE_DP = 40
        private const val ACTION_ICON_PADDING_DP = 8
        private const val ACTIONS_START_MARGIN_DP = 8f
        private const val ACTIONS_END_MARGIN_DP = 4f
        private const val ACTIONS_SPACING_DP = 8
        private const val TITLE_SIDE_MARGIN_DP = 16f
        private const val TITLE_TO_SIDE_SPACING_DP = 16f
        private const val TITLE_SLIDE_OFFSET_DP = 20
        private const val TITLE_SLIDE_MIN_SCALE = 0.3f
        private const val TITLE_SLIDE_MIN_ALPHA = 0f
    }

    private enum class ActionSide {
        LEADING,
        TRAILING
    }

    enum class TitleAnimationMode {
        FADE,
        SLIDE_TOP_DOWN,
        SLIDE_BOTTOM_UP
    }

    data class ActionItem(
        val title: String? = null,
        val iconResId: Int? = null,
        val iconDrawable: Drawable? = null,
        val isEnabled: Boolean = true,
        val onClick: ((view: View) -> Unit)? = null
    )

    init {
        id = generateViewId()
        setBackgroundColor(Color.TRANSPARENT)
    }

    val calculatedMinHeight = defaultHeight.dp

    private fun createTitleLabel(): WLabel {
        return WLabel(context).apply {
            setStyle(22F, WFont.SemiBold)
            setSingleLine()
            ellipsize = TextUtils.TruncateAt.MARQUEE
            isSelected = true
            isHorizontalFadingEdgeEnabled = true
        }
    }

    val titleLabel: WLabel by lazy {
        createTitleLabel()
    }

    val subtitleLabel: WLabel by lazy {
        WLabel(context).apply {
            setStyle(12f, WFont.Medium)
            maxLines = 1
            visibility = GONE
        }
    }

    private val titleContainer: FrameLayout by lazy {
        FrameLayout(context).apply {
            addView(titleLabel, FrameLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        }
    }

    private val titleLinearLayout: LinearLayout by lazy {
        LinearLayout(context).apply {
            id = generateViewId()
            orientation = LinearLayout.VERTICAL
            addView(titleContainer, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
            addView(subtitleLabel, LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        }
    }

    private val leadingActionsContainer: LinearLayout by lazy {
        LinearLayout(context).apply {
            id = generateViewId()
            orientation = LinearLayout.HORIZONTAL
            visibility = GONE
        }
    }

    private val trailingActionsContainer: LinearLayout by lazy {
        LinearLayout(context).apply {
            id = generateViewId()
            orientation = LinearLayout.HORIZONTAL
            visibility = GONE
        }
    }

    private val contentView = WView(context).apply {
        minHeight = calculatedMinHeight
        addView(titleLinearLayout, LayoutParams(0, WRAP_CONTENT))
        addView(
            leadingActionsContainer,
            LayoutParams(WRAP_CONTENT, ACTION_BUTTON_SIZE_DP.dp)
        )
        addView(
            trailingActionsContainer,
            LayoutParams(WRAP_CONTENT, ACTION_BUTTON_SIZE_DP.dp)
        )
    }

    override fun setupViews() {
        super.setupViews()

        minHeight = calculatedMinHeight

        addView(contentView)
        setConstraints {
            allEdges(contentView)
        }
        setOnClickListener { }

        updateLayout()
        updateTheme()
    }

    override fun updateTheme() {
        titleLabel.setTextColor(WColor.PrimaryText.color)
        animatingTitleLabel?.setTextColor(WColor.PrimaryText.color)
        subtitleLabel.setTextColor(WColor.SecondaryText.color)
        updateActionsTheme(
            oldTint = currentTint ?: WColor.SecondaryText,
            newTint = currentTint ?: WColor.SecondaryText,
            animated = false
        )
    }

    var titleAnimationMode = TitleAnimationMode.FADE

    private var oldTitle: String? = null
    fun setTitle(title: String, animated: Boolean) {
        setTitle(title, animated, titleAnimationMode)
    }

    private var animatingTitleLabel: WLabel? = null

    fun setTitle(
        title: String,
        animated: Boolean,
        animationMode: TitleAnimationMode
    ) {
        if (oldTitle == title)
            return
        when {
            !animated -> {
                clearTitleAnimations()
                titleLabel.text = title
            }

            animationMode == TitleAnimationMode.FADE -> {
                clearTitleAnimations()
                if (oldTitle.isNullOrEmpty()) {
                    with(titleLabel) {
                        alpha = 0f
                        text = title
                        animate()
                            .alpha(1f)
                            .setDuration(AnimationConstants.VERY_QUICK_ANIMATION)
                            .setInterpolator(WInterpolator.emphasized)
                    }
                } else {
                    titleLabel.animate()
                        .alpha(0f)
                        .setDuration(AnimationConstants.VERY_QUICK_ANIMATION)
                        .setInterpolator(WInterpolator.emphasized)
                        .withEndAction {
                            titleLabel.text = title
                            titleLabel.animate()
                                .alpha(1f)
                                .setDuration(AnimationConstants.VERY_QUICK_ANIMATION)
                                .setInterpolator(WInterpolator.emphasized)
                        }
                }
            }

            else -> {
                animateTitleVertically(title, animationMode)
            }
        }
        oldTitle = title
    }

    private fun clearTitleAnimations() {
        with(titleLabel) {
            animate().cancel()
            alpha = 1f
            translationY = 0f
        }
        animatingTitleLabel?.animate()?.cancel()
        animatingTitleLabel?.let { titleContainer.removeView(it) }
        animatingTitleLabel = null
    }

    private fun animateTitleVertically(title: String, animationMode: TitleAnimationMode) {
        clearTitleAnimations()

        val offset = maxOf(
            titleContainer.height,
            titleLabel.height,
            titleLabel.lineHeight,
            TITLE_SLIDE_OFFSET_DP.dp
        ).toFloat()
        val incomingStartY =
            if (animationMode == TitleAnimationMode.SLIDE_TOP_DOWN) -offset else offset
        val outgoingEndY = -incomingStartY

        if (!oldTitle.isNullOrEmpty()) {
            animatingTitleLabel = createTitleLabel().apply {
                text = oldTitle
                gravity = titleLabel.gravity
                setTextColor(WColor.PrimaryText.color)
            }.also { oldLabel ->
                titleContainer.addView(
                    oldLabel,
                    FrameLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT)
                )
            }
        }

        with(titleLabel) {
            text = title
            alpha = TITLE_SLIDE_MIN_ALPHA
            scaleX = TITLE_SLIDE_MIN_SCALE
            scaleY = TITLE_SLIDE_MIN_SCALE
            translationY = incomingStartY
        }

        titleContainer.doOnPreDraw {
            animatingTitleLabel?.let { oldLabel ->
                with(oldLabel) {
                    updateTitlePivot(this)
                    scaleX = 1f
                    scaleY = 1f
                    alpha = 1f
                    translationY = 0f
                    animate()
                        .alpha(TITLE_SLIDE_MIN_ALPHA)
                        .scaleX(TITLE_SLIDE_MIN_SCALE)
                        .scaleY(TITLE_SLIDE_MIN_SCALE)
                        .translationY(outgoingEndY)
                        .setDuration(AnimationConstants.VERY_QUICK_ANIMATION)
                        .setInterpolator(WInterpolator.emphasized)
                        .withEndAction {
                            if (animatingTitleLabel === this) {
                                titleContainer.removeView(this)
                                animatingTitleLabel = null
                            }
                        }
                        .start()
                }
            }

            updateTitlePivot(titleLabel)
            titleLabel.animate()
                .alpha(1f)
                .scaleX(1f)
                .scaleY(1f)
                .translationY(0f)
                .setDuration(AnimationConstants.VERY_QUICK_ANIMATION)
                .setInterpolator(WInterpolator.emphasized)
                .start()
        }
    }

    private fun updateTitlePivot(label: WLabel) {
        val layout = label.layout?.takeIf { it.lineCount > 0 } ?: return
        val textLeft = label.totalPaddingLeft + layout.getLineLeft(0)
        val textRight = label.totalPaddingLeft + layout.getLineRight(0)
        label.pivotX = (textLeft + textRight) / 2f
        label.pivotY = label.height / 2f
    }

    private var oldTitleView: View? = null
    fun setTitleView(titleView: View?, animated: Boolean) {
        if (oldTitleView == titleView)
            return

        val showNewView = {
            if (titleView != null) {
                titleLabel.visibility = GONE
                titleLinearLayout.addView(
                    titleView,
                    0,
                    LayoutParams(MATCH_PARENT, WRAP_CONTENT)
                )
                if (animated) {
                    titleView.alpha = 0f
                    titleView.animate()
                        .alpha(1f)
                        .setDuration(AnimationConstants.VERY_QUICK_ANIMATION)
                        .setInterpolator(WInterpolator.emphasized)
                }
            } else {
                titleLabel.visibility = VISIBLE
                if (animated) {
                    titleLabel.alpha = 0f
                    titleLabel.animate()
                        .alpha(1f)
                        .setDuration(AnimationConstants.VERY_QUICK_ANIMATION)
                        .setInterpolator(WInterpolator.emphasized)
                }
            }
            oldTitleView = titleView
        }

        oldTitleView?.let { oldView ->
            if (animated) {
                oldView.animate()
                    .alpha(0f)
                    .setDuration(AnimationConstants.VERY_QUICK_ANIMATION)
                    .setInterpolator(WInterpolator.emphasized)
                    .withEndAction {
                        titleLinearLayout.removeView(oldView)
                        showNewView()
                    }
            } else {
                titleLinearLayout.removeView(oldView)
                showNewView()
            }
        } ?: run {
            if (animated && titleLabel.isVisible && titleView != null) {
                titleLabel.animate()
                    .alpha(0f)
                    .setDuration(AnimationConstants.VERY_QUICK_ANIMATION)
                    .setInterpolator(WInterpolator.emphasized)
                    .withEndAction { showNewView() }
            } else {
                showNewView()
            }
        }
    }

    private var oldSubtitle: String? = null
    fun setSubtitle(subtitle: String?, animated: Boolean) {
        if (oldSubtitle == subtitle)
            return
        subtitleLabel.visibility = if (subtitle.isNullOrEmpty()) GONE else VISIBLE
        if (animated) {
            if (oldSubtitle.isNullOrEmpty()) {
                with(subtitleLabel) {
                    alpha = 0f
                    text = subtitle
                    animate()
                        .alpha(1f)
                        .setDuration(AnimationConstants.VERY_QUICK_ANIMATION)
                        .setInterpolator(WInterpolator.emphasized)
                }
            } else {
                subtitleLabel.animate()
                    .alpha(0f)
                    .setDuration(AnimationConstants.VERY_QUICK_ANIMATION)
                    .setInterpolator(WInterpolator.emphasized)
                    .withEndAction {
                        subtitleLabel.text = subtitle
                        subtitleLabel.animate()
                            .alpha(1f)
                            .setDuration(AnimationConstants.VERY_QUICK_ANIMATION)
                            .setInterpolator(WInterpolator.emphasized)
                    }
            }
        } else {
            subtitleLabel.text = subtitle
        }
        oldSubtitle = subtitle
    }

    private val leadingActions = mutableListOf<ActionItem>()
    private val trailingActions = mutableListOf<ActionItem>()
    private val leadingActionViews = mutableListOf<View>()
    private val trailingActionViews = mutableListOf<View>()

    fun addLeadingAction(action: ActionItem) {
        leadingActions.add(action)
        rebuildActions(ActionSide.LEADING)
    }

    fun addTrailingAction(action: ActionItem) {
        trailingActions.add(action)
        rebuildActions(ActionSide.TRAILING)
    }

    fun clearActions() {
        leadingActions.clear()
        trailingActions.clear()
        rebuildActions(ActionSide.LEADING)
        rebuildActions(ActionSide.TRAILING)
    }

    private fun actionsFor(side: ActionSide) =
        if (side == ActionSide.LEADING) leadingActions else trailingActions

    private fun actionViewsFor(side: ActionSide) =
        if (side == ActionSide.LEADING) leadingActionViews else trailingActionViews

    private fun containerFor(side: ActionSide) =
        if (side == ActionSide.LEADING) leadingActionsContainer else trailingActionsContainer

    private fun rebuildActions(side: ActionSide) {
        val container = containerFor(side)
        val actionViews = actionViewsFor(side)
        val actions = actionsFor(side)

        container.removeAllViews()
        actionViews.clear()

        actions.forEachIndexed { index, action ->
            val actionView = createActionView(action)
            container.addView(
                actionView,
                LinearLayout.LayoutParams(
                    if (action.title != null) WRAP_CONTENT else ACTION_BUTTON_SIZE_DP.dp,
                    if (action.title != null) WRAP_CONTENT else ACTION_BUTTON_SIZE_DP.dp
                ).apply {
                    gravity = Gravity.CENTER_VERTICAL
                    if (index != 0) marginStart = ACTIONS_SPACING_DP.dp
                }
            )
            actionViews.add(actionView)
        }

        container.visibility = if (actions.isNotEmpty()) VISIBLE else GONE
        updateLayout()
    }

    private fun createActionView(action: ActionItem): View {
        val tint = currentTint ?: WColor.SecondaryText
        return if (action.title != null) {
            WLabel(context).apply {
                text = action.title
                setStyle(18f, WFont.Medium)
                gravity = Gravity.CENTER
                setPaddingDp(12, 4, 12, 4)
                setTextColor(tint)
                isTinted = true
                addRippleEffect(WColor.BackgroundRipple.color, 16f.dp)
                isEnabled = action.isEnabled
                if (action.onClick != null) {
                    setOnClickListener {
                        action.onClick.invoke(this)
                    }
                } else {
                    setOnClickListener(null)
                }
            }
        } else {
            WImageButton(context).apply {
                if (action.iconResId != null) {
                    setImageResource(action.iconResId)
                } else if (action.iconDrawable != null) {
                    setImageDrawable(action.iconDrawable)
                }
                isEnabled = action.isEnabled
                setPadding(ACTION_ICON_PADDING_DP.dp)
                if (action.onClick != null) {
                    setOnClickListener {
                        action.onClick.invoke(this)
                    }
                } else {
                    setOnClickListener(null)
                }
                updateColors(tint, WColor.BackgroundRipple)
            }
        }
    }

    private var leadingView: View? = null
    private var trailingView: View? = null

    private fun replaceSideView(
        current: View?,
        new: View,
        layoutParams: LayoutParams,
        store: (View) -> Unit
    ) {
        current?.let { contentView.removeView(it) }
        store(new)
        contentView.addView(new, layoutParams)
        updateLayout()
    }

    fun addLeadingView(
        leadingView: View,
        layoutParams: LayoutParams = LayoutParams(WRAP_CONTENT, WRAP_CONTENT)
    ) {
        replaceSideView(this.leadingView, leadingView, layoutParams) { this.leadingView = it }
    }

    fun addTrailingView(
        trailingView: View,
        layoutParams: LayoutParams = LayoutParams(WRAP_CONTENT, WRAP_CONTENT)
    ) {
        replaceSideView(this.trailingView, trailingView, layoutParams) { this.trailingView = it }
    }

    fun addBottomView(bottomView: View, bottomViewHeight: Int) {
        val newHeight = calculatedMinHeight + bottomViewHeight
        minHeight = newHeight
        layoutParams = layoutParams.apply {
            height = minHeight
        }
        contentView.clipToPadding = false
        contentView.setPadding(0, 0, 0, bottomViewHeight)
        contentView.addView(bottomView, LayoutParams(MATCH_PARENT, bottomViewHeight))
        contentView.setConstraints {
            toCenterX(bottomView)
            toBottomPx(bottomView, -bottomViewHeight)
        }
    }

    private var titleGravity: Int = Gravity.START
    fun setTitleGravity(gravity: Int) {
        titleGravity = gravity
        titleLabel.gravity = gravity
        subtitleLabel.gravity = gravity
        updateTitleConstraints()
    }

    private fun updateLayout() {
        contentView.setConstraints {
            leadingView?.let { view ->
                toTopPx(view, contentMarginTop)
                toBottom(view)
                toStart(view, ACTIONS_START_MARGIN_DP)
            }

            if (leadingActionsContainer.isVisible) {
                toTopPx(leadingActionsContainer, contentMarginTop)
                toBottom(leadingActionsContainer)
                leadingView?.let { view ->
                    startToEnd(leadingActionsContainer, view, TITLE_TO_SIDE_SPACING_DP)
                } ?: run {
                    toStart(leadingActionsContainer, ACTIONS_START_MARGIN_DP)
                }
            }

            trailingView?.let { view ->
                toTopPx(view, contentMarginTop)
                toBottom(view)
                toEnd(view, ACTIONS_END_MARGIN_DP)
            }

            if (trailingActionsContainer.isVisible) {
                toTopPx(trailingActionsContainer, contentMarginTop)
                toBottom(trailingActionsContainer)
                trailingView?.let { view ->
                    endToStart(trailingActionsContainer, view, TITLE_TO_SIDE_SPACING_DP)
                } ?: run {
                    toEnd(trailingActionsContainer, ACTIONS_END_MARGIN_DP)
                }
            }
        }

        updateTitleConstraints()
    }

    private fun updateTitleConstraints() {
        val leadingAnchor = when {
            leadingActionsContainer.isVisible -> leadingActionsContainer
            leadingView != null -> leadingView!!
            else -> null
        }
        val trailingAnchor = when {
            trailingActionsContainer.isVisible -> trailingActionsContainer
            trailingView != null -> trailingView!!
            else -> null
        }

        contentView.setConstraints {
            toTopPx(titleLinearLayout, contentMarginTop)
            toBottom(titleLinearLayout)

            if (titleGravity == Gravity.CENTER) {
                toCenterX(
                    titleLinearLayout,
                    if (leadingAnchor != null || trailingAnchor != null) 24f else TITLE_SIDE_MARGIN_DP
                )
                return@setConstraints
            }

            leadingAnchor?.let {
                startToEnd(titleLinearLayout, it, TITLE_TO_SIDE_SPACING_DP)
            } ?: run {
                toStart(titleLinearLayout, TITLE_SIDE_MARGIN_DP)
            }

            trailingAnchor?.let {
                endToStart(titleLinearLayout, it, TITLE_TO_SIDE_SPACING_DP)
            } ?: run {
                toEnd(titleLinearLayout, TITLE_SIDE_MARGIN_DP)
            }
        }
    }

    var currentTint: WColor? = null
    fun setTint(color: WColor, animated: Boolean) {
        val oldTint = currentTint ?: WColor.SecondaryText
        currentTint = color
        updateActionsTheme(oldTint, color, animated)
    }

    private fun updateActionsTheme(oldTint: WColor, newTint: WColor, animated: Boolean) {
        val previousColor = oldTint.color

        (leadingActionViews + trailingActionViews).forEach { view ->
            when (view) {
                is WImageButton -> {
                    if (animated) {
                        view.drawable?.animateTintColor(previousColor, newTint.color)
                    } else {
                        view.updateColors(newTint, WColor.BackgroundRipple)
                    }
                }

                is WLabel -> {
                    if (animated) {
                        view.animateTextColor(newTint.color)
                    } else {
                        view.setTextColor(newTint)
                    }
                }
            }
        }

        listOfNotNull(
            leadingView as? WImageButton,
            trailingView as? WImageButton
        ).forEach { button ->
            if (animated) {
                button.drawable?.animateTintColor(previousColor, newTint.color)
            } else {
                button.updateColors(newTint, WColor.BackgroundRipple)
            }
        }
    }
}
