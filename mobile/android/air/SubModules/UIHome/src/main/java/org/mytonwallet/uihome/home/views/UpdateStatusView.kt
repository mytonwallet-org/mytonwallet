package org.mytonwallet.uihome.home.views

import android.annotation.SuppressLint
import android.content.Context
import android.text.TextUtils
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.FrameLayout
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WReplaceableLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uicomponents.widgets.fadeOut
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

class UpdateStatusView(
    context: Context,
) : FrameLayout(context),
    WThemedView {

    enum class State {
        WaitingForNetwork,
        Updating,
        Updated
    }

    private val statusReplaceableLabel: WReplaceableLabel by lazy {
        val rLabel = WReplaceableLabel(context)
        rLabel.label.setStyle(16f, WFont.Medium)
        rLabel.label.setSingleLine()
        rLabel.label.ellipsize = TextUtils.TruncateAt.MARQUEE
        rLabel.label.isSelected = true
        rLabel.label.isHorizontalFadingEdgeEnabled = true
        rLabel
    }

    init {
        clipChildren = false
        clipToPadding = false
        addView(statusReplaceableLabel, LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
            gravity = Gravity.CENTER
            bottomMargin = 2.dp
        })

        updateTheme()
    }

    override fun updateTheme() {
        statusReplaceableLabel.label.setTextColor(WColor.PrimaryText.color)
    }

    var state: State? = null
    private var customMessage = ""
    private var targetAlpha = 0f

    private fun setLabelStyle(state: State) {
        if (state == State.Updated) {
            statusReplaceableLabel.label.setStyle(
                20f,
                WFont.SemiBold
            )
        } else {
            statusReplaceableLabel.label.setStyle(
                16f,
                WFont.Medium
            )
        }
        statusReplaceableLabel.label.setTextColor(if (state != State.Updated) WColor.SecondaryText.color else WColor.PrimaryText.color)
    }

    @SuppressLint("SetTextI18n")
    fun setState(
        newState: State,
        handleAnimation: Boolean,
        newCustomMessage: String
    ) {
        // Check if the state has changed
        if (state == null)
            setLabelStyle(newState)
        else
            if (state == newState && (state != State.Updated || customMessage == newCustomMessage)) return

        val prevAlpha = targetAlpha

        when (newState) {
            State.WaitingForNetwork -> {
                targetAlpha = 1f
                statusReplaceableLabel.setText(
                    LocaleController.getString("Waiting for Network"),
                    isLoading = true,
                    animated = handleAnimation,
                    beforeNewTextAppearance = {
                        setLabelStyle(newState)
                    }
                )
            }

            State.Updating -> {
                targetAlpha = 1f
                statusReplaceableLabel.setText(
                    LocaleController.getString("Updating"),
                    isLoading = true,
                    animated = handleAnimation,
                    beforeNewTextAppearance = {
                        setLabelStyle(newState)
                    }
                )
            }

            State.Updated -> {
                if (newCustomMessage.isEmpty()) {
                    targetAlpha = 0f
                } else {
                    targetAlpha = 1f
                    statusReplaceableLabel.setText(
                        newCustomMessage,
                        isLoading = false,
                        animated = handleAnimation,
                        wasHidden = state == State.Updated,
                        beforeNewTextAppearance = {
                            setLabelStyle(newState)
                        }
                    )
                }
            }
        }

        // Update the state
        state = newState
        customMessage = newCustomMessage

        if (handleAnimation) {
            if (prevAlpha != targetAlpha) {
                if (targetAlpha == 1f) {
                    statusReplaceableLabel.alpha = 0f
                    statusReplaceableLabel.fadeIn(AnimationConstants.VERY_QUICK_ANIMATION)
                } else {
                    statusReplaceableLabel.fadeOut(AnimationConstants.VERY_QUICK_ANIMATION) {
                        if (state != newState || customMessage != newCustomMessage)
                            return@fadeOut // Status is already updated
                        statusReplaceableLabel.alpha = 0f
                        statusReplaceableLabel.setText(
                            "",
                            isLoading = false,
                            animated = false,
                            beforeNewTextAppearance = { setLabelStyle(newState) }
                        )
                    }
                }
            }
        } else {
            if (targetAlpha == 0f) {
                statusReplaceableLabel.setText(
                    "",
                    isLoading = false,
                    animated = false,
                    beforeNewTextAppearance = { setLabelStyle(newState) }
                )
            }
        }
    }

}
