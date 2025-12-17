package org.mytonwallet.uihome.home.views

import android.annotation.SuppressLint
import android.content.Context
import android.text.TextUtils
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.FrameLayout
import androidx.core.content.ContextCompat
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WReplaceableLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

class UpdateStatusView(
    context: Context,
) : FrameLayout(context),
    WThemedView {

    sealed class State {
        data object WaitingForNetwork : State()
        data object Updating : State()
        data class Updated(val customText: String) : State()
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

    var onTap: (() -> Unit)? = null

    init {
        clipChildren = false
        clipToPadding = false
        addView(statusReplaceableLabel, LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
            gravity = Gravity.CENTER
            bottomMargin = 2.dp
        })

        updateTheme()

        setOnClickListener {
            onTap?.invoke()
        }
    }

    override fun updateTheme() {
    }

    var state: State? = null
    private var customMessage = ""

    private fun setLabelStyle(state: State) {
        if (state is State.Updated) {
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
        statusReplaceableLabel.label.setTextColor(if (state !is State.Updated) WColor.SecondaryText else WColor.PrimaryText)
    }

    @SuppressLint("SetTextI18n")
    fun setState(
        newState: State,
        handleAnimation: Boolean,
    ) {
        val newCustomMessage = (newState as? State.Updated)?.customText ?: ""
        // Check if the state has changed
        if (state == newState) {
            return
        }

        when (newState) {
            State.WaitingForNetwork -> {
                statusReplaceableLabel.setText(
                    WReplaceableLabel.Config(
                        text = LocaleController.getString("Waiting for Network"),
                        isLoading = true,
                    ),
                    animated = handleAnimation,
                    updateLabelAppearance = {
                        setLabelStyle(newState)
                    }
                )
            }

            State.Updating -> {
                statusReplaceableLabel.setText(
                    WReplaceableLabel.Config(
                        text = LocaleController.getString("Updating"),
                        isLoading = true,
                    ),
                    animated = handleAnimation,
                    updateLabelAppearance = {
                        setLabelStyle(newState)
                    }
                )
            }

            is State.Updated -> {
                statusReplaceableLabel.setText(
                    WReplaceableLabel.Config(
                        text = newCustomMessage,
                        isLoading = false,
                        trailingDrawable = if (newCustomMessage.isEmpty()) null else ContextCompat.getDrawable(
                            context,
                            org.mytonwallet.uihome.R.drawable.ic_expand
                        )!!.apply {
                            setTint(WColor.PrimaryText.color)
                        }
                    ),
                    animated = handleAnimation,
                    updateLabelAppearance = {
                        setLabelStyle(newState)
                    }
                )
            }
        }

        // Update the state
        state = newState
        customMessage = newCustomMessage
    }

}
