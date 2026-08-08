package org.mytonwallet.uihome.wallets.cells

import android.animation.ObjectAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.text.TextUtils
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.ViewConfiguration
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.animation.LinearInterpolator
import kotlin.math.abs
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingLocalized
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.uihome.wallets.MiniCardView

@SuppressLint("ViewConstructor")
class WalletCardCell(
    context: Context,
    cellWidth: Int,
    private val onTouchStart: (view: WView) -> Unit,
    private val onClick: (accountId: MAccount) -> Unit,
    private val onLongClick: (cell: WalletCardCell, view: WView, account: MAccount) -> Unit
) : WCell(context, LayoutParams(MATCH_PARENT, WRAP_CONTENT)),
    WThemedView,
    IWalletCardCell {

    private var account: MAccount? = null
    private var reordering = false
    private val miniCardView = MiniCardView(context, cellWidth)

    private val walletName = WLabel(context).apply {
        setStyle(13f, WFont.Medium)
        setLineHeight(TypedValue.COMPLEX_UNIT_SP, 17f)
        setSingleLine()
        ellipsize = TextUtils.TruncateAt.END
        useCustomEmoji = true
        setTextColor(WColor.PrimaryText)
        gravity = Gravity.CENTER
    }
    private val containerView = object : WView(context) {

        private var downX = 0f
        private var downY = 0f
        private val touchSlop = ViewConfiguration.get(context).scaledTouchSlop
        private val longPressTimeout = ViewConfiguration.getLongPressTimeout().toLong()
        private val handler = Handler(Looper.getMainLooper())
        private var hasPerformedLongClick = false

        @SuppressLint("ClickableViewAccessibility")
        override fun onTouchEvent(event: MotionEvent): Boolean {
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    downX = event.x
                    downY = event.y
                    isPressed = !reordering
                    hasPerformedLongClick = false

                    if (!reordering) {
                        handler.postDelayed({
                            if (isPressed && !reordering) {
                                hasPerformedLongClick = performLongClick()
                                if (hasPerformedLongClick) {
                                    isShowingPopup = true
                                    isPressed = false
                                }
                            }
                        }, longPressTimeout)
                    }

                    onTouchStart(this)
                    requestDisallowInterceptTouchEvent(true)
                }

                MotionEvent.ACTION_MOVE -> {
                    val dx = abs(event.x - downX)
                    val dy = abs(event.y - downY)
                    if (dx >= touchSlop || dy >= touchSlop) {
                        isPressed = false
                    }
                }

                MotionEvent.ACTION_UP -> {
                    if (isPressed && !hasPerformedLongClick) {
                        performClick()
                    }
                    isPressed = false
                }

                MotionEvent.ACTION_CANCEL -> {
                    requestDisallowInterceptTouchEvent(false)
                    isPressed = false
                }
            }
            return false
        }
    }.apply {
        addView(miniCardView, LayoutParams(MATCH_PARENT, 0))
        addView(walletName, LayoutParams(MATCH_PARENT, WRAP_CONTENT))

        setConstraints {
            setDimensionRatio(miniCardView.id, "126:82")
            topToBottom(walletName, miniCardView, 5f)
            toBottom(walletName, 4f)
        }
        setPadding(1.dp, 1.dp, 1.dp, 0)

        setOnClickListener {
            if (!reordering) account?.let { onClick(it) }
        }

        setOnLongClickListener {
            if (reordering) return@setOnLongClickListener true
            account?.let { onLongClick(this@WalletCardCell, this, it) }
            true
        }
    }

    override var isShowingPopup = false
        set(value) {
            if (field != value) {
                field = value
                val finalScale = if (field) 1.05f else 1f
                animate().scaleX(finalScale).scaleY(finalScale).start()
            }
        }

    init {
        setPaddingLocalized(0, 0, 4.dp, 4.dp)
        clipChildren = false
        clipToPadding = false
    }

    override fun setupViews() {
        super.setupViews()

        addView(containerView, LayoutParams(MATCH_PARENT, MATCH_PARENT))
    }

    override fun updateTheme() {
        if (isShowingPopup) {
            containerView.setBackgroundColor(WColor.BackgroundRipple.color, 12f.dp)
        } else {
            containerView.background = null
            containerView.addRippleEffect(WColor.BackgroundRipple.color, 12f.dp)
        }
    }

    fun configure(account: MAccount, reordering: Boolean) {
        this.account = account
        setReordering(reordering)
        miniCardView.configure(account)
        walletName.text = account.name
        updateTheme()
    }

    fun setReordering(reordering: Boolean) {
        this.reordering = reordering
        if (reordering) {
            if (shakeAnimator == null) startShake()
        } else {
            stopShake()
        }
    }

    private var shakeAnimator: ObjectAnimator? = null
    private fun startShake() {
        stopShake()
        shakeAnimator = ObjectAnimator.ofFloat(this, "rotation", 0f, -1f, 2f, -1f, 2f, 0f).apply {
            duration = AnimationConstants.SLOW_ANIMATION
            repeatCount = ObjectAnimator.INFINITE
            interpolator = LinearInterpolator()
            start()
        }
    }

    private fun stopShake() {
        shakeAnimator?.cancel()
        shakeAnimator = null
        rotation = 0f
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        stopShake()
    }

    override fun notifyBalanceChange() {
        miniCardView.notifyBalanceChange()
    }
}
