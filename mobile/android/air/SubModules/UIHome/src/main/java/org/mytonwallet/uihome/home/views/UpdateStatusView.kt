package org.mytonwallet.uihome.home.views

import android.annotation.SuppressLint
import android.content.Context
import android.util.Log
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.widget.FrameLayout
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.WReplaceableLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uicomponents.widgets.fadeOut
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController

class UpdateStatusView(
    context: Context,
) : FrameLayout(context),
    WThemedView {

    sealed class State {
        data object WaitingForNetwork : State()
        data object Updating : State()
        data class Updated(val customText: String) : State()
    }

    private val statusReplaceableLabel = WReplaceableLabel(context)

    var onTap: (() -> Unit)? = null

    init {
        clipChildren = false
        clipToPadding = false
        addView(statusReplaceableLabel, LayoutParams(MATCH_PARENT, 28.dp).apply {
            gravity = Gravity.CENTER
            topMargin = (-2).dp
        })

        updateTheme()

        setOnClickListener {
            onTap?.invoke()
        }
    }

    override fun updateTheme() {
    }

    var state: State? = null
    private var isShowing: Boolean = true
    private var customMessage = ""

    fun setAppearance(isShowing: Boolean, animated: Boolean) {
        if (this.isShowing == isShowing)
            return
        this.isShowing = isShowing
        statusReplaceableLabel.animate().cancel()
        if (!animated) {
            statusReplaceableLabel.alpha = if (isShowing) 1f else 0f
            return
        }
        if (isShowing)
            statusReplaceableLabel.fadeIn()
        else
            statusReplaceableLabel.fadeOut()
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
                )
            }

            State.Updating -> {
                statusReplaceableLabel.setText(
                    WReplaceableLabel.Config(
                        text = LocaleController.getString("Updating"),
                        isLoading = true,
                    ),
                    animated = handleAnimation,
                )
            }

            is State.Updated -> {
                statusReplaceableLabel.setText(
                    WReplaceableLabel.Config(
                        text = newCustomMessage,
                        isLoading = false,
                    ),
                    animated = handleAnimation,
                )
            }
        }

        // Update the state
        state = newState
        customMessage = newCustomMessage
    }

}
