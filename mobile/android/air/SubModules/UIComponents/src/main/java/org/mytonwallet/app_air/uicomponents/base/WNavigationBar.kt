package org.mytonwallet.app_air.uicomponents.base

import android.annotation.SuppressLint
import android.graphics.Color
import android.text.TextUtils
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.LinearLayout
import androidx.core.content.ContextCompat
import androidx.core.view.isVisible
import androidx.core.view.setPadding
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.R
import org.mytonwallet.app_air.uicomponents.extensions.animateTintColor
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WImageButton
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uicomponents.widgets.fadeOut
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

@SuppressLint("ViewConstructor")
class WNavigationBar(
    private val viewController: WViewController,
    defaultHeight: Int = DEFAULT_HEIGHT,
    private val contentMarginTop: Int = 0
) : WView(viewController.navigationController!!.context), WThemedView {

    companion object {
        const val DEFAULT_HEIGHT_THICK = 76
        const val DEFAULT_HEIGHT = 64
        const val DEFAULT_HEIGHT_THIN = 56
        const val DEFAULT_HEIGHT_TINY = 48
    }

    init {
        setBackgroundColor(Color.TRANSPARENT)
    }

    val navigationController: WNavigationController
        get() {
            return viewController.navigationController!!
        }

    val topOffset: Int by lazy {
        if (navigationController.presentationConfig.isBottomSheet &&
            !viewController.isExpandable
        )
            0
        else
            navigationController.getSystemBars().top
    }

    val calculatedMinHeight =
        defaultHeight.dp + topOffset

    val titleLabel: WLabel by lazy {
        WLabel(context).apply {
            setStyle(22F, WFont.SemiBold)
            setSingleLine()
            ellipsize = TextUtils.TruncateAt.MARQUEE
            isSelected = true
            isHorizontalFadingEdgeEnabled = true
        }
    }

    val subtitleLabel: WLabel by lazy {
        WLabel(context).apply {
            setStyle(12f, WFont.Medium)
            maxLines = 1
            visibility = GONE
        }
    }

    private val titleLinearLayout: LinearLayout by lazy {
        LinearLayout(context).apply {
            id = generateViewId()
            orientation = LinearLayout.VERTICAL
            addView(titleLabel, LayoutParams(MATCH_PARENT, WRAP_CONTENT))
            addView(subtitleLabel, LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        }
    }

    private val backButton: WImageButton by lazy {
        WImageButton(context).apply {
            setOnClickListener {
                navigationController.onBackPressed()
            }
            visibility = if (navigationController.isBackAllowed()) VISIBLE else GONE
            val arrowDrawable =
                ContextCompat.getDrawable(
                    context,
                    R.drawable.ic_nav_back
                )
            setImageDrawable(arrowDrawable)
            updateColors(currentTint ?: WColor.SecondaryText, WColor.BackgroundRipple)
        }
    }

    private val closeButton: WImageButton by lazy {
        WImageButton(context).apply {
            val closeDrawable =
                ContextCompat.getDrawable(
                    context,
                    R.drawable.ic_close
                )
            setImageDrawable(closeDrawable)
            updateColors(currentTint ?: WColor.SecondaryText, WColor.BackgroundRipple)
            setPadding(8.dp)
        }
    }

    private val contentView = WView(context).apply {
        minHeight = calculatedMinHeight
        addView(backButton, ViewGroup.LayoutParams(40.dp, 40.dp))
        addView(titleLinearLayout, LayoutParams(0, WRAP_CONTENT))

        setConstraints {
            toTopPx(titleLinearLayout, topOffset + contentMarginTop)
            toBottom(titleLinearLayout)
            toStart(titleLinearLayout, if (backButton.isVisible) 64f else 20f)
            toEnd(titleLinearLayout, 20f)
            toTopPx(backButton, topOffset + contentMarginTop)
            toBottom(backButton)
            toStart(backButton, 8f)
        }
    }

    override fun setupViews() {
        super.setupViews()

        minHeight = calculatedMinHeight

        addView(contentView)
        setConstraints {
            toCenterX(contentView)
            toTop(contentView)
            toBottom(contentView)
        }
        setOnClickListener {
            navigationController.viewControllers.last().scrollToTop()
        }

        updateTheme()
    }

    override fun updateTheme() {
        titleLabel.setTextColor(WColor.PrimaryText.color)
        subtitleLabel.setTextColor(WColor.SecondaryText.color)
    }

    private var oldTitle: String? = null
    fun setTitle(title: String, animated: Boolean) {
        if (oldTitle == title)
            return
        if (animated) {
            if (oldTitle.isNullOrEmpty()) {
                titleLabel.alpha = 0f
                titleLabel.fadeIn(AnimationConstants.VERY_QUICK_ANIMATION)
                titleLabel.text = title
            } else {
                titleLabel.fadeOut(AnimationConstants.VERY_QUICK_ANIMATION) {
                    titleLabel.fadeIn(AnimationConstants.VERY_QUICK_ANIMATION)
                    titleLabel.text = title
                }
            }
        } else {
            titleLabel.text = title
        }
        oldTitle = title
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
                    titleView.fadeIn(AnimationConstants.VERY_QUICK_ANIMATION)
                }
            } else {
                titleLabel.visibility = VISIBLE
                if (animated) {
                    titleLabel.alpha = 0f
                    titleLabel.fadeIn(AnimationConstants.VERY_QUICK_ANIMATION)
                }
            }
            oldTitleView = titleView
        }

        oldTitleView?.let { oldView ->
            if (animated) {
                oldView.fadeOut(AnimationConstants.VERY_QUICK_ANIMATION) {
                    titleLinearLayout.removeView(oldView)
                    showNewView()
                }
            } else {
                titleLinearLayout.removeView(oldView)
                showNewView()
            }
        } ?: run {
            if (animated && titleLabel.isVisible && titleView != null) {
                titleLabel.fadeOut(AnimationConstants.VERY_QUICK_ANIMATION) {
                    showNewView()
                }
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
                subtitleLabel.alpha = 0f
                subtitleLabel.fadeIn(AnimationConstants.VERY_QUICK_ANIMATION)
                subtitleLabel.text = subtitle
            } else {
                subtitleLabel.fadeOut(AnimationConstants.VERY_QUICK_ANIMATION) {
                    subtitleLabel.fadeIn(AnimationConstants.VERY_QUICK_ANIMATION)
                    subtitleLabel.text = subtitle
                }
            }
        } else {
            subtitleLabel.text = subtitle
        }
        oldSubtitle = subtitle
    }

    fun addCloseButton(
        trailingMarginDp: Float? = null,
        onClose: () -> Unit = {
            navigationController.window.dismissLastNav()
        }
    ) {
        contentView.addView(closeButton, LayoutParams(40.dp, 40.dp))
        closeButton.setOnClickListener {
            onClose()
        }
        contentView.setConstraints {
            toTopPx(closeButton, topOffset)
            toBottom(closeButton)
            toEnd(closeButton, trailingMarginDp ?: if (height < DEFAULT_HEIGHT) 11f else 8f)
        }
    }

    private var leadingView: View? = null
    fun addLeadingView(
        leadingView: View,
        layoutParams: LayoutParams = LayoutParams(WRAP_CONTENT, WRAP_CONTENT)
    ) {
        this.leadingView = leadingView
        contentView.addView(leadingView, layoutParams)

        contentView.setConstraints {
            toTopPx(leadingView, topOffset + contentMarginTop)
            toBottom(leadingView)
            toStart(leadingView, 8f)
            startToEnd(titleLinearLayout, leadingView, 4f)
        }
    }

    private var trailingView: View? = null
    fun addTrailingView(
        trailingView: View,
        layoutParams: LayoutParams = LayoutParams(WRAP_CONTENT, WRAP_CONTENT)
    ) {
        this.trailingView = trailingView
        contentView.addView(trailingView, layoutParams)

        contentView.setConstraints {
            toTopPx(trailingView, topOffset + contentMarginTop)
            toBottom(trailingView)
            toEnd(trailingView, 8f)
            endToStart(titleLinearLayout, trailingView, 4f)
        }
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

    fun setTitleGravity(gravity: Int) {
        titleLabel.gravity = gravity
        subtitleLabel.gravity = gravity
        contentView.setConstraints {
            if (gravity == Gravity.CENTER) {
                toCenterX(titleLinearLayout, if (backButton.isVisible) 64f else 24f)
            } else {
                toStart(titleLinearLayout, if (backButton.isVisible) 64f else 24f)
                toEnd(titleLinearLayout, 20f)
            }
        }
    }

    fun fadeOutActions() {
        backButton.isEnabled = false
        backButton.fadeOut {
            backButton.visibility = INVISIBLE
        }
        trailingView?.fadeOut()
    }

    fun fadeInActions() {
        backButton.isEnabled = true
        backButton.visibility = VISIBLE
        backButton.fadeIn()
        trailingView?.fadeIn()
    }

    var expansionValue: Float = 0f
        set(value) {
            field = value
            translationZ = if (value < 1f) -1f else 0f
            val normalizedValue = (value - 0.8f) * 5
            contentView.alpha = normalizedValue
        }

    var currentTint: WColor? = null
    fun setTint(color: WColor, animated: Boolean) {
        if (!animated) {
            backButton.updateColors(color)
            (trailingView as? WImageButton)?.updateColors(color)
            currentTint = color
            return
        }
        backButton.drawable?.animateTintColor(
            currentTint?.color ?: WColor.SecondaryText.color,
            color.color
        )
        (trailingView as? WImageButton)?.drawable?.animateTintColor(
            currentTint?.color ?: WColor.SecondaryText.color,
            color.color
        )
        currentTint = color
    }

    fun setOnBackPressed(onBackPressed: OnClickListener) {
        backButton.setOnClickListener(onBackPressed)
    }
}
