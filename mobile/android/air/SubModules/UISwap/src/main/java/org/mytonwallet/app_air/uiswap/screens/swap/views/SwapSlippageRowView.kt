package org.mytonwallet.app_air.uiswap.screens.swap.views

import android.annotation.SuppressLint
import android.content.Context
import android.content.res.ColorStateList
import android.graphics.Canvas
import android.text.InputType
import android.text.method.DigitsKeyListener
import android.view.Gravity
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.LinearLayout
import androidx.core.content.ContextCompat
import androidx.core.widget.doOnTextChanged
import me.vkryl.core.parseFloat
import org.mytonwallet.app_air.uicomponents.drawable.SeparatorBackgroundDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.ViewHelpers
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WAmountEditText
import org.mytonwallet.app_air.uicomponents.widgets.WButton
import org.mytonwallet.app_air.uicomponents.widgets.WEditableItemView
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.addRippleEffect
import org.mytonwallet.app_air.uicomponents.widgets.animateHeight
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uicomponents.widgets.fadeOut
import org.mytonwallet.app_air.uicomponents.widgets.hideKeyboard
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

@SuppressLint("ViewConstructor")
class SwapSlippageRowView(
    context: Context,
    private val onSlippageChange: (Float) -> Unit
) : WView(context),
    WThemedView {
    private val separator = SeparatorBackgroundDrawable().apply {
        offsetStart = 20f.dp
        offsetEnd = 20f.dp
    }
    private val rippleDrawable = ViewHelpers.roundedRippleDrawable(separator, 0, 0f)

    private var currentVal: Float = 5f

    private val titleLabel = WLabel(context).apply {
        setStyle(16f)
        text = LocaleController.getString("Slippage")
    }

    private val infoDrawable =
        ContextCompat.getDrawable(context, org.mytonwallet.app_air.icons.R.drawable.ic_info_24)!!
            .apply {
                alpha = 128
            }

    private val valueView = WEditableItemView(context).apply {
        id = generateViewId()
        drawable = ContextCompat.getDrawable(
            context,
            org.mytonwallet.app_air.icons.R.drawable.ic_arrows_18
        )
        setText("${currentVal.toInt()}%")
    }

    private val doneButton = WLabel(context).apply {
        text = LocaleController.getString("Save")
        alpha = 0f
        isClickable = false
        setTextColor(WColor.Tint)
        setStyle(16f, WFont.Medium)
        setPadding(8.dp, 0, 8.dp, 0)
        gravity = Gravity.CENTER_VERTICAL
    }

    private val slippageEditText = WAmountEditText(context, isLeadingSymbol = false).apply {
        setBaseCurrencySymbol("%")
        setPadding(12.dp, 0, 0, 0)
        setText("${currentVal.toInt()}")
        inputType = InputType.TYPE_NUMBER_FLAG_DECIMAL
        keyListener = DigitsKeyListener.getInstance("0123456789.,")
        doOnTextChanged { text, _, _, _ ->
            val num = parseFloat(text.toString())
            setTextColor(if (num > 0 && num <= 50) WColor.PrimaryText.color else WColor.Red.color)
        }
    }

    private val editorView = LinearLayout(context).apply {
        id = generateViewId()
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        setPadding(16.dp, 0, 24.dp, 0)
        arrayOf(0.5, 1, 2, 5, 10).forEach { num ->
            addView(WButton(context, WButton.Type.SECONDARY).apply {
                setText("$num%")
                layoutParams = LayoutParams(40.dp, WRAP_CONTENT).apply {
                    marginStart = 4.dp
                }
                setOnClickListener {
                    slippageEditText.setText(num.toString())
                }
            })
        }
        addView(WView(context).apply {
            layoutParams = LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
                weight = 1f
            }
        })
        addView(slippageEditText)
        setOnClickListener { }
        visibility = GONE
    }

    init {
        layoutParams = ViewGroup.LayoutParams(MATCH_PARENT, 56.dp)
    }

    @SuppressLint("SetTextI18n")
    override fun setupViews() {
        super.setupViews()

        background = rippleDrawable

        addView(titleLabel, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        addView(doneButton, LayoutParams(WRAP_CONTENT, 36.dp))
        addView(valueView, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        addView(editorView, LayoutParams(MATCH_PARENT, 50.dp))
        setConstraints {
            toStart(titleLabel, 20f)
            toTop(titleLabel, 16f)
            toTop(doneButton, 10f)
            toEnd(doneButton, 20f)
            toTop(valueView, 10f)
            toEnd(valueView, 20f)
            toTop(editorView, 46f)
        }
        valueView.setOnClickListener {
            toggle()
        }
        doneButton.setOnClickListener {
            val num = parseFloat(slippageEditText.text.toString())
            val isNumAcceptable = num > 0 && num <= 50
            if (isNumAcceptable) {
                valueView.setText("${if (num % 1 == 0f) num.toInt() else num}%")
                currentVal = num
                onSlippageChange(num)
            }
            toggle()
        }

        updateTheme()
    }

    override fun updateTheme() {
        rippleDrawable.setColor(ColorStateList.valueOf(WColor.backgroundRippleColor))
        infoDrawable.setTint(WColor.SecondaryText.color)
        titleLabel.setTextColor(WColor.SecondaryText.color)
        doneButton.addRippleEffect(WColor.TintRipple.color, 18f.dp)
    }

    private var isExpanded = false
    private var animationInProgress = false
    private fun toggle() {
        if (animationInProgress)
            return

        isExpanded = !isExpanded
        animationInProgress = true
        valueView.isClickable = !isExpanded
        doneButton.isClickable = isExpanded

        if (isExpanded) {
            slippageEditText.setText("${if (currentVal % 1 == 0f) currentVal.toInt() else currentVal}")
            slippageEditText.setTextColor(WColor.PrimaryText.color)
            animateHeight(96.dp)
            editorView.fadeIn()
            valueView.fadeOut {
                doneButton.fadeIn {
                    animationInProgress = false
                }
            }
            editorView.visibility = VISIBLE
        } else {
            hideKeyboard()
            animateHeight(56.dp)
            editorView.fadeOut {
                editorView.visibility = GONE
            }
            doneButton.fadeOut {
                valueView.fadeIn {
                    animationInProgress = false
                }
            }
        }
    }

    override fun dispatchDraw(canvas: Canvas) {
        super.dispatchDraw(canvas)

        infoDrawable.let {
            val y = (56.dp - it.minimumHeight) / 2
            val x = if (LocaleController.isRTL) {
                titleLabel.left - 4.dp - it.minimumWidth
            } else {
                titleLabel.right + 4.dp
            }

            it.setBounds(x, y, x + it.minimumWidth, y + it.minimumHeight)
            it.draw(canvas)
        }
    }
}
