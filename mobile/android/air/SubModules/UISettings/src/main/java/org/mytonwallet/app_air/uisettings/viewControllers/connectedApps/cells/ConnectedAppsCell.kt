package org.mytonwallet.app_air.uisettings.viewControllers.connectedApps.cells

import android.content.Context
import android.text.TextUtils
import android.util.TypedValue
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.appcompat.widget.AppCompatTextView
import androidx.core.content.ContextCompat
import androidx.core.net.toUri
import androidx.core.view.isGone
import androidx.customview.widget.ViewDragHelper
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.ViewHelpers
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.swipeRevealLayout.SwipeRevealLayout
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.uicomponents.image.WCustomImageView
import org.mytonwallet.app_air.uicomponents.widgets.WBaseView
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcore.moshi.ApiDapp

class ConnectedAppsCell(context: Context) :
    WCell(context, LayoutParams(MATCH_PARENT, WRAP_CONTENT)), WThemedView {

    companion object {
        private const val MAIN_VIEW_RADIUS = 18f
    }

    private val lastItemRadius = (ViewConstants.BLOCK_RADIUS - 1.5f).dp

    private val redRipple = WRippleDrawable.create(0f).apply {
        backgroundColor = WColor.Red.color
        rippleColor = WColor.BackgroundRipple.color
    }

    private fun getRedRippleForLastItem() = WRippleDrawable.create(
        0f,
        0f,
        ViewConstants.BLOCK_RADIUS.dp,
        ViewConstants.BLOCK_RADIUS.dp
    ).apply {
        backgroundColor = WColor.Red.color
        rippleColor = WColor.BackgroundRipple.color
    }

    private val imageView = WCustomImageView(context).apply {
        layoutParams = LayoutParams(40.dp, 40.dp)
        defaultRounding = Content.Rounding.Radius(8f.dp)
    }

    private val titleLabel = AppCompatTextView(context).apply {
        id = generateViewId()
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
        setLineHeight(TypedValue.COMPLEX_UNIT_SP, 24f)
        includeFontPadding = false
        ellipsize = TextUtils.TruncateAt.END
        typeface = WFont.Medium.typeface
        maxLines = 1
    }

    private val subtitleLabel = AppCompatTextView(context).apply {
        id = generateViewId()
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
        setLineHeight(TypedValue.COMPLEX_UNIT_SP, 20f)
        includeFontPadding = false
        ellipsize = TextUtils.TruncateAt.END
        typeface = WFont.Regular.typeface
        maxLines = 1
    }

    val mainView = WView(context, LayoutParams(MATCH_PARENT, WRAP_CONTENT)).apply {

        addView(imageView)
        addView(titleLabel, LayoutParams(0, WRAP_CONTENT))
        addView(subtitleLabel, LayoutParams(0, 22.dp))
        setConstraints {
            toCenterY(imageView, 12f)
            toStart(imageView, 16f)
            topToTop(titleLabel, imageView)
            startToEnd(titleLabel, imageView, 12f)
            toEnd(titleLabel, 24f)
            bottomToBottom(subtitleLabel, imageView, -2f)
            startToEnd(subtitleLabel, imageView, 12f)
            toEnd(subtitleLabel, 24f)
        }
    }

    private val disconnectLabel = AppCompatTextView(context).apply {
        id = generateViewId()
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
        setLineHeight(TypedValue.COMPLEX_UNIT_SP, 24f)
        includeFontPadding = false
        ellipsize = TextUtils.TruncateAt.END
        typeface = WFont.Medium.typeface
        maxLines = 1
        text = LocaleController.getString("Disconnect")
    }

    val secondaryView = WView(context).apply {
        id = generateViewId()
        layoutParams = LayoutParams(WRAP_CONTENT, WRAP_CONTENT)
        background = redRipple

        addView(disconnectLabel, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        setConstraints {
            toCenterY(disconnectLabel)
            toCenterX(disconnectLabel, 20f)
        }
    }

    val swipeRevealLayout = SwipeRevealLayout(context).apply {
        id = generateViewId()
        layoutParams = LayoutParams(MATCH_PARENT, WRAP_CONTENT)
        dragEdge = SwipeRevealLayout.DRAG_EDGE_RIGHT
        isFullOpenEnabled = true
        setSwipeListener(object : SwipeRevealLayout.SwipeListener {
            override fun onClosed(view: SwipeRevealLayout?) {
                mainView.background = ViewHelpers.roundedShapeDrawable(
                    WColor.Background.color,
                    0f,
                    0f,
                    if (isLast) lastItemRadius else 0f,
                    if (isLast) lastItemRadius else 0f
                )
            }

            override fun onOpened(view: SwipeRevealLayout?) {
                mainView.background = ViewHelpers.roundedShapeDrawable(
                    WColor.Background.color,
                    0f,
                    MAIN_VIEW_RADIUS,
                    if (isLast) maxOf(
                        MAIN_VIEW_RADIUS,
                        lastItemRadius
                    ) else MAIN_VIEW_RADIUS,
                    0f
                )
            }

            override fun onFullyOpened(view: SwipeRevealLayout?) {
                onDisconnectDApp?.invoke()
            }

            override fun onSlide(view: SwipeRevealLayout?, slideOffset: Float) {
                val multiplier = if (slideOffset < 0.02) 0f else slideOffset * 4f
                val variableRadius =
                    if (multiplier >= 1f) MAIN_VIEW_RADIUS else MAIN_VIEW_RADIUS * multiplier
                val bottomRadius = if (isLast) lastItemRadius else 0f

                mainView.background = ViewHelpers.roundedShapeDrawable(
                    WColor.Background.color,
                    0f,
                    variableRadius,
                    if (isLast) maxOf(variableRadius, bottomRadius) else variableRadius,
                    bottomRadius
                )
            }

        })
        setViewDragHelperStateChangeListener {
            when (it) {
                ViewDragHelper.STATE_DRAGGING -> {
                    parent.requestDisallowInterceptTouchEvent(true)
                }

                ViewDragHelper.STATE_IDLE -> {
                    parent.requestDisallowInterceptTouchEvent(false)
                }
            }
        }

        addView(secondaryView)
        addView(mainView)
        initChildren()
    }

    private var containerView: WViewController.ContainerView? = null

    init {
        addView(swipeRevealLayout)
        setConstraints {
            allEdges(swipeRevealLayout)
        }

        post {
            val secondaryViewLayoutParams = secondaryView.layoutParams
            secondaryViewLayoutParams.height = mainView.height
            secondaryView.layoutParams = secondaryViewLayoutParams

            getContainerView()
        }

        updateTheme()
    }

    fun closeSwipe() {
        swipeRevealLayout.close(true)
    }

    override fun updateTheme() {
        mainView.setBackgroundColor(
            WColor.Background.color,
            0f,
            if (isLast) lastItemRadius else 0f
        )

        if (isLast) {
            val lastItemRedRipple = getRedRippleForLastItem()
            secondaryView.background = lastItemRedRipple
            swipeRevealLayout.setBackgroundColor(
                WColor.Red.color,
                0f,
                ViewConstants.BLOCK_RADIUS.dp
            )
        } else {
            redRipple.backgroundColor = WColor.Red.color
            redRipple.rippleColor = WColor.BackgroundRipple.color
            secondaryView.background = redRipple
            swipeRevealLayout.setBackgroundColor(WColor.Red.color)
        }

        titleLabel.setTextColor(WColor.PrimaryText.color)
        subtitleLabel.setTextColor(WColor.SecondaryText.color)
        disconnectLabel.setTextColor(WColor.TextOnTint.color)
    }

    private var isLast = false
    private var onDisconnectDApp: (() -> Unit)? = null
    private var onWarningTapped: (() -> Unit)? = null

    fun configure(
        exploreSite: ApiDapp,
        isLast: Boolean,
        onDisconnect: () -> Unit,
        onWarning: (() -> Unit)? = null
    ) {
        this.isLast = isLast
        exploreSite.iconUrl?.let { iconUrl ->
            imageView.set(Content(image = Content.Image.Url(iconUrl)))
        } ?: run {
            imageView.clear()
        }
        titleLabel.text = exploreSite.name
        subtitleLabel.text = exploreSite.url?.toUri()?.host
        subtitleLabel.gravity = Gravity.CENTER_VERTICAL

        if (exploreSite.isUrlEnsured != true) {
            val warningIcon = ContextCompat.getDrawable(
                context,
                org.mytonwallet.app_air.walletcontext.R.drawable.ic_warning
            )
            warningIcon?.let { drawable ->
                drawable.setBounds(0, 0, 14.dp, 14.dp)
                subtitleLabel.setCompoundDrawablesRelativeWithIntrinsicBounds(
                    drawable, null, null, null
                )
                subtitleLabel.compoundDrawablePadding = 4.dp
            }

            subtitleLabel.setOnClickListener {
                onWarning?.invoke()
            }
            onWarningTapped = onWarning
        } else {
            subtitleLabel.setCompoundDrawablesRelativeWithIntrinsicBounds(
                null, null, null, null
            )
            subtitleLabel.setOnClickListener(null)
            onWarningTapped = null
        }

        onDisconnectDApp = onDisconnect

        updateTheme()
    }

    private fun getContainerView() {
        var view = parent
        while (view !is WViewController.ContainerView && view != null) {
            view = view.parent
        }
        if (view is WViewController.ContainerView) containerView = view
    }
}
