package org.mytonwallet.app_air.uiinappbrowser.views

import android.annotation.SuppressLint
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Color
import android.os.Handler
import android.os.Looper
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.TextUtils
import android.view.Gravity
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.core.content.ContextCompat
import androidx.core.graphics.ColorUtils
import androidx.core.net.toUri
import androidx.core.view.setPadding
import org.mytonwallet.app_air.icons.R
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.resize
import org.mytonwallet.app_air.uicomponents.helpers.HapticType
import org.mytonwallet.app_air.uicomponents.helpers.Haptics
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.uicomponents.image.WCustomImageView
import org.mytonwallet.app_air.uicomponents.widgets.BackDrawable
import org.mytonwallet.app_air.uicomponents.widgets.WImageButton
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uicomponents.widgets.fadeOut
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup.BackgroundStyle
import org.mytonwallet.app_air.uiinappbrowser.InAppBrowserVC
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.theme.colorForTheme
import org.mytonwallet.app_air.walletcontext.utils.VerticalImageSpan
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha
import org.mytonwallet.app_air.walletcore.models.InAppBrowserConfig
import java.lang.ref.WeakReference
import kotlin.math.roundToInt

@SuppressLint("ViewConstructor")
class InAppBrowserTopBarView(
    private val viewController: InAppBrowserVC,
    private val tabBarController: WNavigationController.ITabBarController?,
    private val options: List<InAppBrowserConfig.Option>?,
    private var selectedOption: String?,
    private val optionsOnTitle: Boolean,
    private val minimizeStarted: () -> Unit,
    private val maximizeFinished: () -> Unit,
) : WView(viewController.context), WThemedView {

    private val moreButtonRipple = WRippleDrawable.create(20f.dp)
    private val minimizeButtonRipple = WRippleDrawable.create(20f.dp)
    private val backButtonRipple = WRippleDrawable.create(100f.dp)

    private val backDrawable = BackDrawable(context, false).apply {
        setRotation(1f, false)
    }

    private val iconView = WCustomImageView(context).apply {
        defaultRounding = Content.Rounding.Radius(8f.dp)
        alpha = 0f
    }

    private val titleLabel: WLabel by lazy {
        WLabel(context).apply {
            setStyle(22F, WFont.SemiBold)
            gravity = Gravity.CENTER_VERTICAL or
                if (LocaleController.isRTL) Gravity.RIGHT else Gravity.LEFT
            setSingleLine()
            ellipsize = TextUtils.TruncateAt.MARQUEE
            isHorizontalFadingEdgeEnabled = true
            pivotX = 0f
            if (optionsOnTitle && !options.isNullOrEmpty()) {
                text = textWithArrow(options.find { it.identifier == selectedOption }?.title, true)
                setOnClickListener {
                    showOptionsMenu(this)
                }
            }
        }
    }

    fun textWithArrow(txt: String?, isTitle: Boolean): SpannableStringBuilder? {
        val txt = txt ?: return null
        val ss = SpannableStringBuilder(txt)
        ContextCompat.getDrawable(
            context,
            R.drawable.ic_arrows_14
        )?.let { drawable ->
            drawable.mutate()
            drawable.setTint(
                (if (isTitle) WColor.PrimaryText else WColor.SecondaryText).colorForTheme(
                    overrideThemeIsDark
                )
            )
            val arrowScale = if (isTitle) 1f else 0.8f
            val width = 7.dp * arrowScale
            val height = 14.dp * arrowScale
            val yOffset = (if (isTitle) 1f else 0.5f).dp.roundToInt()
            drawable.setBounds(5.dp, yOffset, width.roundToInt() + 5.dp, height.roundToInt() + yOffset)
            val imageSpan = VerticalImageSpan(drawable)
            ss.append(" ", imageSpan, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        }
        return ss
    }

    private fun showOptionsMenu(anchorView: WLabel) {
        WMenuPopup.present(
            anchorView,
            options?.map { option ->
                WMenuPopup.Item(
                    WMenuPopup.Item.Config.SelectableItem(
                        option.title,
                        null,
                        selectedOption == option.identifier
                    ),
                    onTap = {
                        selectedOption = option.identifier
                        if (optionsOnTitle) {
                            titleLabel.text = textWithArrow(option.title, true)
                            subtitleLabel.text = option.subtitle
                        } else {
                            subtitleLabel.text = textWithArrow(option.title, false)
                        }
                        option.onClick(WeakReference(viewController))
                    }
                )
            } ?: emptyList(),
            positioning = WMenuPopup.Positioning.BELOW,
            windowBackgroundStyle = BackgroundStyle.Cutout.fromView(
                view = anchorView,
                roundRadius = 8f.dp,
                horizontalOffset = 8.dp,
                verticalOffset = 0
            ),
            xOffset = (-8).dp
        )
    }

    private val subtitleLabel: WLabel by lazy {
        WLabel(context).apply {
            setTextColor(WColor.SecondaryText)
            setStyle(12f, WFont.Medium)
            gravity = Gravity.CENTER_VERTICAL or
                if (LocaleController.isRTL) Gravity.RIGHT else Gravity.LEFT
            setSingleLine()
            ellipsize = TextUtils.TruncateAt.MARQUEE
            isHorizontalFadingEdgeEnabled = true
            pivotX = 0f
            if (optionsOnTitle) {
                text = options?.find { it.identifier == selectedOption }?.subtitle
            } else {
                text =
                    textWithArrow(options?.find { it.identifier == selectedOption }?.title, false)
                setOnClickListener {
                    showOptionsMenu(this)
                }
            }
        }
    }

    private val backButton: WImageButton by lazy {
        val btn = object : WImageButton(context) {
            override fun updateTheme() {}
        }
        btn.setImageDrawable(backDrawable)
        btn.setOnClickListener {
            backPressed()
        }
        btn
    }

    private val minimizeButton: WImageButton by lazy {
        val v = WImageButton(context)
        v.setPadding(8.dp)
        v.setOnClickListener {
            minimize()
        }
        v
    }

    private val moreButton: WImageButton by lazy {
        val v = WImageButton(context)
        v.setPadding(8.dp)
        v
    }

    override fun setupViews() {
        super.setupViews()

        minHeight =
            (if (options.isNullOrEmpty()) WNavigationBar.DEFAULT_HEIGHT_TINY else WNavigationBar.DEFAULT_HEIGHT).dp +
                (viewController.navigationController?.getSystemBars()?.top ?: 0)
        maxHeight = minHeight
        addView(titleLabel, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        if (!options.isNullOrEmpty())
            addView(subtitleLabel, LayoutParams(0, WRAP_CONTENT))
        addView(backButton, ViewGroup.LayoutParams(40.dp, 40.dp))
        addView(moreButton, LayoutParams(40.dp, 40.dp))
        if (tabBarController != null) {
            addView(minimizeButton, LayoutParams(40.dp, 40.dp))
        }
        moreButton.setOnClickListener {
            morePressed()
        }
        setOnClickListener {
            tabBarController?.maximize()
        }
        addView(iconView, LayoutParams(24.dp, 24.dp))

        setConstraints {
            setHorizontalBias(titleLabel.id, 0f)
            constrainedWidth(titleLabel.id, true)
            startToEnd(titleLabel, backButton, 8f)
            endToStart(titleLabel, if (tabBarController != null) minimizeButton else moreButton, 8f)
            if (options.isNullOrEmpty()) {
                toTopPx(titleLabel, viewController.navigationController?.getSystemBars()?.top ?: 0)
                toBottom(titleLabel)
            } else {
                toTopPx(
                    titleLabel,
                    8.dp + (viewController.navigationController?.getSystemBars()?.top ?: 0)
                )
                startToStart(subtitleLabel, titleLabel, 1f)
                topToBottom(subtitleLabel, titleLabel)
            }
            toTopPx(iconView, viewController.navigationController?.getSystemBars()?.top ?: 0)
            toBottom(iconView)
            startToStart(iconView, titleLabel, 4f)
            toTopPx(backButton, viewController.navigationController?.getSystemBars()?.top ?: 0)
            toBottom(backButton)
            toStart(backButton, 16f)
            toTopPx(moreButton, viewController.navigationController?.getSystemBars()?.top ?: 0)
            toBottom(moreButton)
            toEnd(moreButton, 16f)
            if (tabBarController != null) {
                endToStart(minimizeButton, moreButton, 4f)
                toTopPx(
                    minimizeButton,
                    viewController.navigationController?.getSystemBars()?.top ?: 0
                )
                toBottom(minimizeButton)
            }
        }

        setBackgroundColor(Color.TRANSPARENT)
        updateTheme()
    }

    var overrideThemeIsDark: Boolean? = null
        set(value) {
            field = value
            updateTheme()
        }

    override fun updateTheme() {
        val shouldRenderMinimized = isMinimizing || isMinimized
        val shouldRenderAsDarkMode = if (shouldRenderMinimized) null else overrideThemeIsDark
        if (isMinimizing || isMinimized) {
            setBackgroundColor(WColor.SearchFieldBackground.color)
            backDrawable.setColor(WColor.PrimaryText.color)
            backDrawable.setRotatedColor(WColor.PrimaryText.color)
        } else {
            backDrawable.setColor(WColor.SecondaryText.colorForTheme(shouldRenderAsDarkMode))
            backDrawable.setRotatedColor(WColor.SecondaryText.colorForTheme(shouldRenderAsDarkMode))
        }
        titleLabel.animateTextColor(WColor.PrimaryText.colorForTheme(shouldRenderAsDarkMode))
        val moreDrawable =
            ContextCompat.getDrawable(
                context,
                R.drawable.ic_more
            )?.apply {
                setTint(WColor.SecondaryText.colorForTheme(shouldRenderAsDarkMode))
            }
        moreButton.setImageDrawable(moreDrawable)
        moreButton.background = moreButtonRipple
        moreButtonRipple.backgroundColor = Color.TRANSPARENT
        moreButtonRipple.rippleColor = WColor.BackgroundRipple.colorForTheme(shouldRenderAsDarkMode)
        val minimizeDrawable =
            ContextCompat.getDrawable(
                context,
                R.drawable.ic_arrow_up_24
            )?.apply {
                setTint(WColor.SecondaryText.colorForTheme(shouldRenderAsDarkMode))
            }?.resize(context, 24.dp, 24.dp)
        minimizeButton.rotation = 180f
        minimizeButton.setImageDrawable(minimizeDrawable)
        minimizeButton.background = minimizeButtonRipple
        minimizeButtonRipple.backgroundColor = Color.TRANSPARENT
        minimizeButtonRipple.rippleColor = WColor.BackgroundRipple.colorForTheme(shouldRenderAsDarkMode)
        if (!options.isNullOrEmpty()) {
            if (optionsOnTitle) {
                titleLabel.text =
                    textWithArrow(options.find { it.identifier == selectedOption }?.title, true)
            } else {
                subtitleLabel.text =
                    textWithArrow(options.find { it.identifier == selectedOption }?.title, false)
            }
        }
        backButton.background = backButtonRipple
        backButtonRipple.backgroundColor = Color.TRANSPARENT
        backButtonRipple.rippleColor = WColor.SecondaryBackground.colorForTheme(shouldRenderAsDarkMode)
    }

    fun blendColors(color1: Int, color2: Int, ratio: Float): Int {
        return ColorUtils.blendARGB(color1, color2, ratio)
    }

    var isMinimized = false
    var isMinimizing = false
    private fun minimize() {
        if (isMinimizing)
            return
        if (isMinimized) {
            tabBarController?.maximize()
            return
        }
        isMinimizing = true
        minimizeStarted()
        viewController.view.post {
            titleLabel.pivotY = titleLabel.height / 2f
            backDrawable.setRotation(1f, true)
            titleLabel.animateTextColor(WColor.PrimaryText.color)
            tabBarController?.minimize(viewController.navigationController!!, onProgress = {
                val heightDiff = (viewController.navigationController?.getSystemBars()?.top ?: 0)
                val parent = parent as ViewGroup
                parent.layoutParams = (parent.layoutParams as MarginLayoutParams).apply {
                    topMargin = (-it * heightDiff).roundToInt()
                }
                moreButton.layoutParams = (moreButton.layoutParams as MarginLayoutParams).apply {
                    rightMargin = (16.dp - it * 56.dp).roundToInt()
                }
                backButton.layoutParams = (backButton.layoutParams as MarginLayoutParams).apply {
                    leftMargin = (4.dp + (1 - it) * 12.dp).roundToInt()
                }
                titleLabel.scaleX = 1 - 0.23f * it
                titleLabel.scaleY = titleLabel.scaleX
                minimizeButton.rotation = (1 - it) * 180
                setBackgroundColor(WColor.SearchFieldBackground.color.colorWithAlpha((it * 255).toInt()))
                val drawableColor =
                    blendColors(
                        WColor.SecondaryText.color,
                        WColor.PrimaryLightText.color,
                        it
                    )
                backDrawable.setColor(drawableColor)
                backDrawable.setRotatedColor(drawableColor)
                minimizeButton.drawable.setTint(drawableColor)
                titleLabel.translationX = 36f.dp * it
                iconView.alpha = it
                if (it == 1f) {
                    isMinimized = true
                    isMinimizing = false
                }
            }, onMaximizeProgress = {
                if (it == 0f) {
                    updateBackButton(true)
                }
                val heightDiff = (viewController.navigationController?.getSystemBars()?.top ?: 0)
                val parent = parent as ViewGroup
                parent.layoutParams = (parent.layoutParams as MarginLayoutParams).apply {
                    topMargin = (-(1 - it) * heightDiff).roundToInt()
                }
                moreButton.layoutParams = (moreButton.layoutParams as MarginLayoutParams).apply {
                    rightMargin = (16.dp - (1 - it) * 56.dp).roundToInt()
                }
                backButton.layoutParams = (backButton.layoutParams as MarginLayoutParams).apply {
                    leftMargin = (4.dp + it * 12.dp).roundToInt()
                }
                titleLabel.scaleX = 1 - 0.23f * (1 - it)
                titleLabel.scaleY = titleLabel.scaleX
                titleLabel.animateTextColor(WColor.PrimaryText.colorForTheme(overrideThemeIsDark))
                minimizeButton.rotation = it * 180
                titleLabel.setTextColor(
                    blendColors(
                        WColor.SecondaryText.color,
                        WColor.PrimaryText.color,
                        it
                    )
                )
                setBackgroundColor(WColor.SearchFieldBackground.color.colorWithAlpha(((1 - it) * 255).toInt()))
                val drawableColor =
                    blendColors(
                        WColor.PrimaryText.color,
                        WColor.SecondaryText.color,
                        it
                    )
                backDrawable.setColor(drawableColor)
                backDrawable.setRotatedColor(drawableColor)
                minimizeButton.drawable.setTint(drawableColor)
                titleLabel.translationX = 36f.dp * (1 - it)
                iconView.alpha = 1 - it
                if (it == 1f) {
                    isMinimized = false
                    isMinimizing = false
                    maximizeFinished()
                }
            })
        }
    }

    fun backPressed() {
        if (isMinimizing)
            return
        if (isMinimized) {
            tabBarController?.dismissMinimized()
            return
        }
        if (viewController.webView.canGoBack()) {
            viewController.webView.goBack()
            updateBackButton(true)
        } else {
            if (viewController.window?.isAnimating == true)
                return
            viewController.window?.dismissLastNav()
        }
    }

    private var isShowingBackArrow = false
    fun updateBackButton(animated: Boolean) {
        isShowingBackArrow = if (viewController.webView.canGoBack() && !isShowingBackArrow) {
            true
        } else if (!viewController.webView.canGoBack() && isShowingBackArrow) {
            false
        } else {
            return
        }
        backDrawable.setRotation(if (isShowingBackArrow) 0f else 1f, animated)
    }

    private fun morePressed() {
        val activeUrl = viewController.webView.url ?: viewController.config.url
        WMenuPopup.present(
            moreButton,
            listOf(
                WMenuPopup.Item(
                    null,
                    LocaleController.getString("Reload")
                ) {
                    viewController.webView.reload()
                },
                WMenuPopup.Item(
                    null,
                    LocaleController.getString("Open in Browser")
                ) {
                    val intent = Intent(Intent.ACTION_VIEW)
                    intent.setData(activeUrl.toUri())
                    viewController.window?.startActivity(intent)
                },
                WMenuPopup.Item(
                    null,
                    LocaleController.getString("CopyURL")
                ) {
                    val clipboard =
                        context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                    val clip =
                        ClipData.newPlainText(
                            LocaleController.getString("CopyURL"),
                            activeUrl
                        )
                    clipboard.setPrimaryClip(clip)
                    Haptics.play(context, HapticType.LIGHT_TAP)
                },
                WMenuPopup.Item(
                    null,
                    LocaleController.getString("Share")
                ) {
                    val shareIntent = Intent(Intent.ACTION_SEND)
                    shareIntent.setType("text/plain")
                    shareIntent.putExtra(Intent.EXTRA_TEXT, activeUrl)
                    viewController.window?.startActivity(
                        Intent.createChooser(
                            shareIntent,
                            LocaleController.getString("Share")
                        )
                    )
                }),
            popupWidth = WRAP_CONTENT,
            positioning = WMenuPopup.Positioning.ALIGNED
        )
    }

    private fun startMarquee() {
        Handler(Looper.getMainLooper()).postDelayed({
            titleLabel.isSelected = true
        }, 2000)
    }

    fun updateTitle(newTitle: String, animated: Boolean) {
        titleLabel.isSelected = false
        if (!animated) {
            titleLabel.text = newTitle
            startMarquee()
            return
        }
        titleLabel.fadeOut {
            titleLabel.text = newTitle
            titleLabel.fadeIn {
                startMarquee()
            }
        }
    }

    fun setIconUrl(url: String) {
        if (tabBarController == null)
            return
        iconView.set(Content.ofUrl(url))
    }

    fun setIconBitmap(bitmap: Bitmap?) {
        if (tabBarController == null)
            return
        iconView.setImageBitmap(bitmap)
    }
}
