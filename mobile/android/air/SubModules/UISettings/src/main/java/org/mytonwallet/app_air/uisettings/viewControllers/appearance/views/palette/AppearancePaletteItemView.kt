package org.mytonwallet.app_air.uisettings.viewControllers.appearance.views.palette

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.graphics.drawable.Drawable
import android.view.Gravity
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.appcompat.widget.AppCompatImageView
import androidx.core.content.ContextCompat
import androidx.core.graphics.toColorInt
import androidx.core.view.isGone
import com.google.android.material.progressindicator.CircularProgressIndicator
import org.mytonwallet.app_air.uicomponents.R
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setMarginsDp
import org.mytonwallet.app_air.uicomponents.widgets.WFrameLayout
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.theme.DEFAULT_TINT_DARK
import org.mytonwallet.app_air.walletbasecontext.theme.DEFAULT_TINT_LIGHT
import org.mytonwallet.app_air.walletbasecontext.theme.NftAccentColors
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager.isDark
import org.mytonwallet.app_air.walletcontext.utils.solidColorWithAlpha

@SuppressLint("ViewConstructor")
class AppearancePaletteItemView(
    context: Context,
    val nftAccentId: Int?,
    val onTap: (nftAccentId: Int?, state: State) -> Unit
) : WFrameLayout(context), WThemedView {
    enum class State {
        LOADING,
        LOCKED,
        AVAILABLE,
        SELECTED,
    }

    var state: State = State.LOADING

    init {
        setOnClickListener {
            onTap(nftAccentId, state)
        }
    }

    private var lockDrawable: Drawable? = null
    private var lockView: AppCompatImageView? = null
    private var selectedItemView: View? = null
    private var progressIndicator: CircularProgressIndicator? = null
    var isLoading: Boolean = false
        set(value) {
            field = value
            updateLoadingState()
        }

    fun configure(state: State) {
        this.state = state
        when (state) {
            State.LOCKED -> {
                isLoading = false
                selectedItemView?.isGone = true
                if (lockView == null) {
                    lockDrawable = ContextCompat.getDrawable(
                        context,
                        R.drawable.ic_lock_item
                    )
                    lockView = AppCompatImageView(context).apply {
                        setImageDrawable(lockDrawable)
                    }
                    addView(lockView, LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
                        gravity = Gravity.CENTER
                    })
                } else {
                    lockView?.isGone = false
                }
            }

            State.SELECTED -> {
                isLoading = false
                lockView?.isGone = true
                if (selectedItemView == null) {
                    selectedItemView = View(context)
                    addView(selectedItemView, LayoutParams(MATCH_PARENT, MATCH_PARENT).apply {
                        setMarginsDp(2)
                    })
                } else {
                    selectedItemView?.isGone = false
                }
            }

            State.LOADING -> {
                isLoading = true
                lockView?.isGone = true
                selectedItemView?.isGone = true
            }

            State.AVAILABLE -> {
                isLoading = false
                lockView?.isGone = true
                selectedItemView?.isGone = true
            }
        }
        updateTheme()
    }

    val textOnTint: Int
        get() {
            return if (nftAccentId != 16 || !isDark) Color.WHITE else Color.BLACK
        }

    override fun updateTheme() {
        val color =
            nftAccentId?.let { (if (isDark) NftAccentColors.dark else NftAccentColors.light)[nftAccentId].toColorInt() }
                ?: (if (isDark) DEFAULT_TINT_DARK else DEFAULT_TINT_LIGHT)
        setBackgroundColor(color, 17f.dp)
        val textOnTint = textOnTint
        selectedItemView?.setBackgroundColor(
            color,
            17f.dp,
            17f.dp,
            true,
            textOnTint,
            3.dp
        )
        lockDrawable?.apply {
            setTint(textOnTint.solidColorWithAlpha(128))
        }
        progressIndicator?.setIndicatorColor(textOnTint)
    }

    private fun updateLoadingState() {
        if (isLoading && progressIndicator == null) {
            progressIndicator = CircularProgressIndicator(context).apply {
                id = generateViewId()
                isIndeterminate = true
                indicatorSize = 16.dp
                setIndicatorColor(textOnTint)
            }
            addView(
                progressIndicator,
                LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
                    gravity = Gravity.CENTER
                }
            )
        }
        if (isLoading) {
            progressIndicator?.visibility = VISIBLE
        } else {
            progressIndicator?.visibility = GONE
        }
    }
}
