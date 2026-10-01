package org.mytonwallet.app_air.uicomponents.commonViews

import android.annotation.SuppressLint
import android.content.Context
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.widget.FrameLayout
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WReplaceableLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uicomponents.widgets.fadeOut
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor

@SuppressLint("ViewConstructor")
class UpdateStatusView(context: Context, private val style: Style = Style.Header) :
    FrameLayout(context),
    WThemedView {

    companion object {
        private const val LOADING_TEXT_SIZE = 16f
        private val LOADING_FONT = WFont.Medium
        private const val LOADED_TEXT_SIZE = 20f
        private val LOADED_FONT = WFont.Medium
        private const val NAV_TEXT_SIZE = 18f
        private const val NAV_INDICATOR_SIZE = 24
        private const val NAV_INDICATOR_STROKE = 2.5f
    }

    enum class Style { Header, NavigationBar }

    sealed class State {
        data object WaitingForNetwork : State()
        data object Updating : State()
        data class Updated(val customText: String) : State()
    }

    private val statusReplaceableLabel = when (style) {
        Style.Header -> WReplaceableLabel(context)

        Style.NavigationBar -> WReplaceableLabel(
            context,
            drawableSize = NAV_INDICATOR_SIZE.dp,
            progressStrokeWidthDp = NAV_INDICATOR_STROKE,
            useMarquee = false
        ).apply {
            setGravity(Gravity.START or Gravity.CENTER_VERTICAL)
        }
    }

    var onTap: (() -> Unit)? = null
    var onLongTap: (() -> Unit)? = null

    init {
        clipChildren = false
        clipToPadding = false
        setPadding(1.dp, 0, 1.dp, 0)
        addView(
            statusReplaceableLabel,
            LayoutParams(MATCH_PARENT, 28.dp).apply {
                gravity = Gravity.CENTER
                topMargin = (-2).dp
            }
        )

        updateTheme()

        setOnClickListener {
            onTap?.invoke()
        }
        setOnLongClickListener {
            if (state is State.Updated) {
                onLongTap?.invoke()
                true
            } else {
                false
            }
        }
    }

    override fun updateTheme() {
    }

    private val loadingTextSize = when (style) {
        Style.Header -> LOADING_TEXT_SIZE
        Style.NavigationBar -> NAV_TEXT_SIZE
    }

    var state: State? = null
    private var isShowing: Boolean = true
    private var customMessage = ""

    fun setAppearance(isShowing: Boolean, animated: Boolean) {
        if (this.isShowing == isShowing) return
        this.isShowing = isShowing
        isClickable = isShowing
        isLongClickable = isShowing
        statusReplaceableLabel.animate().cancel()
        if (!animated) {
            statusReplaceableLabel.isProgressAnimated = isShowing
            statusReplaceableLabel.alpha = if (isShowing) 1f else 0f
            return
        }
        if (isShowing) {
            statusReplaceableLabel.isProgressAnimated = true
            statusReplaceableLabel.fadeIn()
        } else {
            statusReplaceableLabel.fadeOut { statusReplaceableLabel.isProgressAnimated = false }
        }
    }

    @SuppressLint("SetTextI18n")
    fun setState(newState: State, handleAnimation: Boolean) {
        val newCustomMessage = (newState as? State.Updated)?.customText ?: ""
        // Check if the state has changed
        if (state == newState) {
            return
        }

        when (newState) {
            State.WaitingForNetwork -> {
                statusReplaceableLabel.setText(
                    WReplaceableLabel.Config(
                        text = when (style) {
                            Style.Header -> LocaleController.getString("Waiting for Network")

                            Style.NavigationBar ->
                                LocaleController.getString("Waiting for network…")
                        },
                        isLoading = true,
                        isExpandable = false,
                        textColor = WColor.SecondaryText,
                        textSize = loadingTextSize,
                        font = LOADING_FONT
                    ),
                    animated = handleAnimation
                )
            }

            State.Updating -> {
                statusReplaceableLabel.setText(
                    when (style) {
                        Style.Header -> WReplaceableLabel.Config(
                            text = LocaleController.getString("Updating"),
                            isLoading = true,
                            isExpandable = false,
                            textColor = WColor.SecondaryText,
                            textSize = loadingTextSize,
                            font = LOADING_FONT
                        )

                        Style.NavigationBar -> WReplaceableLabel.Config(
                            text = LocaleController.getString("Updating…"),
                            isLoading = true,
                            isExpandable = false,
                            textColor = WColor.PrimaryText,
                            textSize = loadingTextSize,
                            font = LOADING_FONT,
                            progressColor = WColor.Tint
                        )
                    },
                    animated = handleAnimation
                )
            }

            is State.Updated -> {
                statusReplaceableLabel.setText(
                    WReplaceableLabel.Config(
                        text = if (style == Style.Header) newCustomMessage else "",
                        isLoading = false,
                        isExpandable = style == Style.Header,
                        textColor = WColor.PrimaryText,
                        textSize = LOADED_TEXT_SIZE,
                        font = LOADED_FONT
                    ),
                    animated = handleAnimation
                )
            }
        }

        // Update the state
        state = newState
        customMessage = newCustomMessage
    }
}
