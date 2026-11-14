package org.mytonwallet.app_air.uiinappbrowser.views

import android.annotation.SuppressLint
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.TextUtils
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.core.graphics.ColorUtils
import androidx.core.graphics.createBitmap
import androidx.core.net.toUri
import androidx.core.view.setPadding
import java.lang.ref.WeakReference
import kotlin.math.min
import kotlin.math.roundToInt
import org.mytonwallet.app_air.icons.R
import org.mytonwallet.app_air.uicomponents.R as UIComponentsR
import org.mytonwallet.app_air.uicomponents.base.ITabsVC
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.extensions.asImage
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.getLtrBaselineSpacingOffset
import org.mytonwallet.app_air.uicomponents.extensions.resize
import org.mytonwallet.app_air.uicomponents.extensions.startActivityCatching
import org.mytonwallet.app_air.uicomponents.glass.GlassProviders
import org.mytonwallet.app_air.uicomponents.glass.WGlassView
import org.mytonwallet.app_air.uicomponents.helpers.ClipboardHelpers
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
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uicomponents.widgets.fadeOut
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup.BackgroundStyle
import org.mytonwallet.app_air.uicomponents.widgets.setOnMenuClickListener
import org.mytonwallet.app_air.uiinappbrowser.InAppBrowserVC
import org.mytonwallet.app_air.uiinappbrowser.MinimizedBrowserTabsVC
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.theme.colorForTheme
import org.mytonwallet.app_air.walletbasecontext.utils.getDrawableCompat
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.utils.VerticalImageSpan
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha
import org.mytonwallet.app_air.walletcore.models.InAppBrowserConfig

@SuppressLint("ViewConstructor")
class InAppBrowserTopBarView(
    private val viewController: InAppBrowserVC,
    private val options: List<InAppBrowserConfig.Option>?,
    private var selectedOption: String?,
    private val optionsOnTitle: Boolean,
    private val minimizeStarted: (onReady: () -> Unit) -> Unit,
    private val minimizeFinished: () -> Unit,
    private val maximizeStarted: () -> Unit,
    private val maximizeFinished: () -> Unit
) : WView(viewController.context),
    WThemedView {

    private val minimizedBrowser get() = viewController.window?.minimizedBrowser

    private val minimizedBlurRoot
        get() = (viewController.window?.minimizedBrowserAnchor as? ITabsVC)?.minimizedBlurRootView
    private val useMinimizedBlur get() = minimizedBlurRoot != null

    private var minimizedBlurView: WGlassView? = null
    private var minimizedBlurViewRoot: ViewGroup? = null

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
            id = UIComponentsR.id.browser_title
            setStyle(22F, WFont.Medium)
            gravity = Gravity.CENTER_VERTICAL or
                if (LocaleController.isRTL) Gravity.RIGHT else Gravity.LEFT
            setSingleLine()
            ellipsize = TextUtils.TruncateAt.MARQUEE
            isHorizontalFadingEdgeEnabled = true
            pivotX = 0f
            if (LocaleController.isRTL) {
                addOnLayoutChangeListener { v, _, _, _, _, _, _, _, _ ->
                    v.pivotX =
                        v.width.toFloat()
                }
            }
            useCustomEmoji = true
            if (optionsOnTitle && !options.isNullOrEmpty()) {
                text = textWithArrow(options.find { it.identifier == selectedOption }?.title, true)
                setOnMenuClickListener {
                    showOptionsMenu(this)
                }
            }
        }
    }

    fun textWithArrow(txt: String?, isTitle: Boolean): SpannableStringBuilder? {
        val txt = txt ?: return null
        val ss = SpannableStringBuilder(txt)
        context.getDrawableCompat(R.drawable.ic_arrows_14)?.let { drawable ->
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
            drawable.setBounds(
                0,
                yOffset,
                width.roundToInt(),
                height.roundToInt() + yOffset
            )
            val imageSpan = VerticalImageSpan(
                drawable,
                startPadding = 5.dp
            )
            ss.append(" ", imageSpan, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        }
        return ss
    }

    private fun showOptionsMenu(anchorView: WLabel) {
        viewController.webView.setLayerType(View.LAYER_TYPE_HARDWARE, null)
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
            backdropStyle = WMenuPopup.BackdropStyle.Transparent,
            xOffset = (-8).dp,
            onDidDismiss = ::onMenuDismissed
        )
    }

    private val subtitleLabel: WLabel by lazy {
        WLabel(context).apply {
            id = UIComponentsR.id.browser_subtitle
            setTextColor(WColor.SecondaryText)
            setStyle(12f, WFont.Medium)
            gravity = Gravity.CENTER_VERTICAL or
                if (LocaleController.isRTL) Gravity.RIGHT else Gravity.LEFT
            setSingleLine()
            ellipsize = TextUtils.TruncateAt.MARQUEE
            isHorizontalFadingEdgeEnabled = true
            pivotX = 0f
            useCustomEmoji = true
            if (optionsOnTitle) {
                text = options?.find { it.identifier == selectedOption }?.subtitle
            } else {
                text =
                    textWithArrow(options?.find { it.identifier == selectedOption }?.title, false)
                setOnMenuClickListener {
                    showOptionsMenu(this)
                }
            }
        }
    }

    private val backButton: WImageButton by lazy {
        val btn = object : WImageButton(context) {
            override fun updateTheme() {}
        }
        btn.id = UIComponentsR.id.browser_back
        btn.setImageDrawable(backDrawable)
        btn.setOnClickListener {
            backPressed()
        }
        btn
    }

    private val minimizeButton: WImageButton by lazy {
        val v = WImageButton(context)
        v.id = UIComponentsR.id.browser_minimize
        v.setPadding(8.dp)
        val minimizeDrawable =
            context.getDrawableCompat(
                R.drawable.ic_arrow_up_24
            )?.resize(context, 24.dp, 24.dp)
        v.setImageDrawable(minimizeDrawable)
        v.setOnClickListener {
            minimize()
        }
        v
    }

    private val moreButton: WImageButton by lazy {
        val v = WImageButton(context)
        v.id = UIComponentsR.id.browser_more
        v.setPadding(8.dp)
        v.setImageDrawable(
            context.getDrawableCompat(R.drawable.ic_more)
        )
        v
    }

    override fun setupViews() {
        super.setupViews()

        minHeight =
            (
                if (options.isNullOrEmpty()) {
                    WNavigationBar.DEFAULT_HEIGHT_TINY
                } else {
                    WNavigationBar.DEFAULT_HEIGHT
                }
                ).dp +
            (viewController.navigationController?.getSystemBars()?.top ?: 0)
        maxHeight = minHeight
        addView(titleLabel, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        if (!options.isNullOrEmpty()) {
            addView(subtitleLabel, LayoutParams(0, WRAP_CONTENT))
            subtitleLabel.translationY =
                titleLabel.paint.getLtrBaselineSpacingOffset(subtitleLabel.paint)
        }
        addView(backButton, ViewGroup.LayoutParams(40.dp, 40.dp))
        addView(moreButton, LayoutParams(40.dp, 40.dp))
        addView(minimizeButton, LayoutParams(40.dp, 40.dp))
        moreButton.setOnMenuClickListener {
            morePressed()
        }
        setOnClickListener {
            openFromMinimized()
        }
        addView(iconView, LayoutParams(24.dp, 24.dp))

        setConstraints {
            setHorizontalBias(titleLabel.id, 0f)
            constrainedWidth(titleLabel.id, true)
            startToEnd(titleLabel, backButton, 8f)
            endToStart(titleLabel, minimizeButton, 8f)
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
            endToStart(minimizeButton, moreButton, 4f)
            toTopPx(
                minimizeButton,
                viewController.navigationController?.getSystemBars()?.top ?: 0
            )
            toBottom(minimizeButton)
        }

        setBackgroundColor(Color.TRANSPARENT)
        updateTheme()
    }

    fun insetsUpdated() {
        val topInset = viewController.navigationController?.getSystemBars()?.top ?: 0
        minHeight =
            (
                if (options.isNullOrEmpty()) {
                    WNavigationBar.DEFAULT_HEIGHT_TINY
                } else {
                    WNavigationBar.DEFAULT_HEIGHT
                }
                ).dp +
            topInset
        maxHeight = minHeight
        setConstraints {
            if (options.isNullOrEmpty()) {
                toTopPx(titleLabel, topInset)
                toBottom(titleLabel)
            } else {
                toTopPx(titleLabel, 8.dp + topInset)
            }
            toTopPx(iconView, topInset)
            toBottom(iconView)
            toTopPx(backButton, topInset)
            toBottom(backButton)
            toTopPx(moreButton, topInset)
            toBottom(moreButton)
            toTopPx(minimizeButton, topInset)
            toBottom(minimizeButton)
        }
    }

    var overrideThemeIsDark: Boolean? = null
        set(value) {
            field = value
            updateTheme()
        }

    private fun syncBlurView() {
        val blurRoot = minimizedBlurRoot
        if (minimizedBlurView != null && minimizedBlurViewRoot === blurRoot) return
        minimizedBlurView?.let { removeView(it) }
        minimizedBlurView = null
        minimizedBlurViewRoot = blurRoot
        if (blurRoot == null) return
        minimizedBlurView = WGlassView(context).also {
            it.setProvider(GlassProviders.plain(WColor.Background))
            it.setupWith(blurRoot)
            it.alpha = 0f
            addView(it, 0, LayoutParams(MATCH_PARENT, MATCH_PARENT))
        }
    }

    override fun updateTheme() {
        val shouldRenderMinimized = isMinimizing || isMinimized
        val shouldRenderAsDarkMode = if (shouldRenderMinimized) null else overrideThemeIsDark
        val tintColor =
            if (shouldRenderMinimized) {
                WColor.PrimaryText.color
            } else {
                WColor.SecondaryText.colorForTheme(
                    shouldRenderAsDarkMode
                )
            }
        if (shouldRenderMinimized) {
            syncBlurView()
            if (useMinimizedBlur) {
                setBackgroundColor(Color.TRANSPARENT)
                minimizedBlurView?.alpha = 1f
                minimizedBlurView?.updateTheme()
            } else {
                setBackgroundColor(WColor.SearchFieldBackground.color)
            }
        }
        backDrawable.setColor(tintColor)
        backDrawable.setRotatedColor(tintColor)
        titleLabel.animateTextColor(WColor.PrimaryText.colorForTheme(shouldRenderAsDarkMode))
        moreButton.drawable.setTint(WColor.SecondaryText.colorForTheme(shouldRenderAsDarkMode))
        moreButton.background = moreButtonRipple
        moreButtonRipple.backgroundColor = Color.TRANSPARENT
        moreButtonRipple.rippleColor = WColor.BackgroundRipple.colorForTheme(shouldRenderAsDarkMode)
        minimizeButton.rotation = if (shouldRenderMinimized) 0f else 180f
        minimizeButton.drawable.setTint(tintColor)
        minimizeButton.background = minimizeButtonRipple
        minimizeButtonRipple.backgroundColor = Color.TRANSPARENT
        minimizeButtonRipple.rippleColor =
            WColor.BackgroundRipple.colorForTheme(shouldRenderAsDarkMode)
        if (!options.isNullOrEmpty()) {
            if (optionsOnTitle) {
                setTitleText(
                    textWithArrow(options.find { it.identifier == selectedOption }?.title, true)
                )
            } else {
                subtitleLabel.text =
                    textWithArrow(options.find { it.identifier == selectedOption }?.title, false)
            }
        }
        backButton.background = backButtonRipple
        backButtonRipple.backgroundColor = Color.TRANSPARENT
        backButtonRipple.rippleColor =
            WColor.BackgroundRipple.colorForTheme(shouldRenderAsDarkMode)
    }

    fun blendColors(color1: Int, color2: Int, ratio: Float): Int =
        ColorUtils.blendARGB(color1, color2, ratio)

    private fun applyMinimizedBackground(fraction: Float) {
        val f = fraction.coerceIn(0f, 1f)
        syncBlurView()
        if (useMinimizedBlur) {
            setBackgroundColor(Color.TRANSPARENT)
            minimizedBlurView?.alpha = f
        } else {
            setBackgroundColor(WColor.SearchFieldBackground.color.colorWithAlpha((f * 255).toInt()))
        }
    }

    private val titleShift get() = if (LocaleController.isRTL) -36f.dp else 36f.dp

    var isMinimized = false
    var isMinimizing = false
    private var isMaximizing = false
    private fun minimize() {
        if (isMinimizing) return
        if (isMinimized) {
            openFromMinimized()
            return
        }
        isMinimizing = true
        stopMarquee()
        viewController.navigationController?.let { minimizedBrowser?.prepareMinimize(it) }
        minimizeStarted {
            val navigationController = viewController.navigationController ?: run {
                minimizedBrowser?.cancelMinimize()
                return@minimizeStarted
            }
            titleLabel.pivotY = titleLabel.height / 2f
            backDrawable.setRotation(1f, true)
            titleLabel.animateTextColor(WColor.PrimaryText.color)
            val hasOptions = !options.isNullOrEmpty()
            val iconOffsetY = if (hasOptions) {
                val titleCenterY = titleLabel.top + titleLabel.height / 2f
                val iconCenterY = iconView.top + iconView.height / 2f
                titleCenterY - iconCenterY
            } else {
                0f
            }
            titleLabel.setLayerType(LAYER_TYPE_HARDWARE, null)
            minimizedBrowser?.minimize(navigationController, onProgress = {
                val heightDiff = (viewController.navigationController?.getSystemBars()?.top ?: 0)
                val parent = parent as? ViewGroup
                parent?.layoutParams = (parent?.layoutParams as? MarginLayoutParams)?.apply {
                    topMargin = (-it * heightDiff).roundToInt()
                }
                moreButton.layoutParams = (moreButton.layoutParams as MarginLayoutParams).apply {
                    marginEnd = (16.dp - it * 56.dp).roundToInt()
                }
                backButton.layoutParams = (backButton.layoutParams as MarginLayoutParams).apply {
                    marginStart = (4.dp + (1 - it) * 12.dp).roundToInt()
                }
                titleLabel.scaleX = 1 - 0.23f * it
                titleLabel.scaleY = titleLabel.scaleX
                minimizeButton.rotation = (1 - it) * 180
                applyMinimizedBackground(it)
                val drawableColor =
                    blendColors(
                        WColor.SecondaryText.color,
                        WColor.PrimaryText.color,
                        it
                    )
                backDrawable.setColor(drawableColor)
                backDrawable.setRotatedColor(drawableColor)
                minimizeButton.drawable.setTint(drawableColor)
                titleLabel.translationX = titleShift * it
                iconView.alpha = it
                if (hasOptions) {
                    subtitleLabel.alpha = 1 - it
                    iconView.translationY = iconOffsetY * it
                    backButton.translationY = iconOffsetY * it
                    minimizeButton.translationY = iconOffsetY * it
                }
                if (it == 1f) {
                    titleLabel.setLayerType(LAYER_TYPE_NONE, null)
                    isMinimized = true
                    isMinimizing = false
                    titleLabel.isClickable = false
                    titleLabel.isLongClickable = false
                    updateStackTitle()
                    startMarquee()
                    minimizeFinished()
                }
            }, onMaximizeProgress = {
                if (it == 0f) {
                    isMaximizing = true
                    stopMarquee()
                    titleLabel.setLayerType(LAYER_TYPE_HARDWARE, null)
                    restoreStackTitle()
                    maximizeStarted()
                    updateBackButton(true)
                    titleLabel.isClickable = true
                    titleLabel.isLongClickable = true
                }
                val heightDiff = (viewController.navigationController?.getSystemBars()?.top ?: 0)
                val parent = parent as? ViewGroup
                parent?.layoutParams = (parent?.layoutParams as? MarginLayoutParams)?.apply {
                    topMargin = (-(1 - it) * heightDiff).roundToInt()
                }
                moreButton.layoutParams = (moreButton.layoutParams as MarginLayoutParams).apply {
                    marginEnd = (16.dp - (1 - it) * 56.dp).roundToInt()
                }
                backButton.layoutParams = (backButton.layoutParams as MarginLayoutParams).apply {
                    marginStart = (4.dp + it * 12.dp).roundToInt()
                }
                titleLabel.scaleX = 1 - 0.23f * (1 - it)
                titleLabel.scaleY = titleLabel.scaleX
                val titleColor = WColor.PrimaryText.colorForTheme(overrideThemeIsDark)
                // A non-animated maximize reports 0 and 1 at once.
                if (it > 0f && it < 1f) titleLabel.animateTextColor(titleColor)
                minimizeButton.rotation = it * 180
                titleLabel.setTextColor(
                    if (it == 1f) {
                        titleColor
                    } else {
                        blendColors(WColor.SecondaryText.color, WColor.PrimaryText.color, it)
                    }
                )
                applyMinimizedBackground(1 - it)
                val drawableColor =
                    blendColors(
                        WColor.PrimaryText.color,
                        WColor.SecondaryText.color,
                        it
                    )
                backDrawable.setColor(drawableColor)
                backDrawable.setRotatedColor(drawableColor)
                minimizeButton.drawable.setTint(drawableColor)
                titleLabel.translationX = titleShift * (1 - it)
                iconView.alpha = 1 - it
                if (hasOptions) {
                    subtitleLabel.alpha = it
                    iconView.translationY = iconOffsetY * (1 - it)
                    backButton.translationY = iconOffsetY * (1 - it)
                    minimizeButton.translationY = iconOffsetY * (1 - it)
                }
                if (it == 1f) {
                    titleLabel.setLayerType(LAYER_TYPE_NONE, null)
                    isMinimized = false
                    isMinimizing = false
                    isMaximizing = false
                    startMarquee()
                    maximizeFinished()
                }
            }, onStateChanged = {
                if (isMinimized) applyMinimizedBackground(1f)
                updateStackTitle()
            })
        }
    }

    private fun openFromMinimized() {
        val presenter = minimizedBrowser ?: return
        if (presenter.count > 1) {
            val window = viewController.window ?: return
            val nav = WNavigationController(
                window,
                WNavigationController.PresentationConfig(
                    style = WNavigationController.PresentationStyle.Overlay
                )
            )
            nav.setRoot(MinimizedBrowserTabsVC(context))
            window.present(nav, animated = false)
        } else {
            presenter.maximize(
                WGlobalStorage.getAreAnimationsActive(),
                viewController.navigationController
            )
        }
    }

    private var titleBeforeStack: CharSequence? = null

    private fun setTitleText(text: CharSequence?) {
        if (titleBeforeStack == null) {
            titleLabel.text = text
            return
        }
        titleBeforeStack = text
        updateStackTitle()
    }

    private fun updateStackTitle() {
        val presenter = minimizedBrowser
        val nav = viewController.navigationController
        val moreCount =
            if (isMinimized && nav != null && presenter?.isFront(nav) == true) {
                presenter.count - 1
            } else {
                0
            }
        if (moreCount <= 0) {
            restoreStackTitle()
            return
        }
        val baseTitle = titleBeforeStack ?: titleLabel.text.also { titleBeforeStack = it }
        val stackTitle = (if (LocaleController.isRTL) "\u200F" else "") +
            LocaleController.getPlural(moreCount, "\$browser_more_tabs")
                .replace("%title%", baseTitle?.toString().orEmpty())
        if (titleLabel.text?.toString() != stackTitle) titleLabel.text = stackTitle
    }

    private fun restoreStackTitle() {
        val title = titleBeforeStack ?: return
        titleBeforeStack = null
        titleLabel.text = title
    }

    fun backPressed() {
        if (isMinimizing) return
        if (isMinimized) {
            minimizedBrowser?.dismissMinimized(
                WGlobalStorage.getAreAnimationsActive(),
                viewController.navigationController
            )
            return
        }
        if (viewController.webView.canGoBack()) {
            viewController.webView.goBack()
            updateBackButton(true)
        } else {
            if (viewController.window?.isAnimating == true) return
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
        viewController.webView.setLayerType(View.LAYER_TYPE_HARDWARE, null)
        WMenuPopup.present(
            moreButton,
            listOf(
                WMenuPopup.Item(
                    null,
                    LocaleController.getString("Reload")
                ) {
                    viewController.webView.reload()
                }.apply { testViewId = UIComponentsR.id.browser_menu_reload },
                WMenuPopup.Item(
                    null,
                    LocaleController.getString("Open in Browser")
                ) {
                    viewController.window?.startActivityCatching(
                        Intent(Intent.ACTION_VIEW, activeUrl.toUri())
                    )
                }.apply { testViewId = UIComponentsR.id.browser_menu_open_external },
                WMenuPopup.Item(
                    null,
                    LocaleController.getString("CopyURL")
                ) {
                    if (ClipboardHelpers.copyToClipboard(
                            context,
                            LocaleController.getString("CopyURL"),
                            activeUrl
                        )
                    ) {
                        Haptics.play(context, HapticType.LIGHT_TAP)
                    }
                }.apply { testViewId = UIComponentsR.id.browser_menu_copy_url },
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
                }.apply { testViewId = UIComponentsR.id.browser_menu_share }
            ),
            popupWidth = WRAP_CONTENT,
            positioning = WMenuPopup.Positioning.ALIGNED,
            backdropStyle = WMenuPopup.BackdropStyle.Transparent,
            onDidDismiss = ::onMenuDismissed
        )
    }

    private fun onMenuDismissed() {
        viewController.webView.setLayerType(View.LAYER_TYPE_NONE, null)
    }

    private val marqueeRunnable = Runnable {
        if (!isMinimizing && !isMaximizing) titleLabel.isSelected = true
    }

    private fun startMarquee() {
        titleLabel.removeCallbacks(marqueeRunnable)
        titleLabel.postDelayed(marqueeRunnable, 2000)
    }

    private fun stopMarquee() {
        titleLabel.removeCallbacks(marqueeRunnable)
        titleLabel.isSelected = false
    }

    fun updateTitle(newTitle: String, animated: Boolean) {
        if (titleBeforeStack != null) {
            setTitleText(newTitle)
            return
        }
        stopMarquee()
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

    var iconUrl: String? = null
        private set
    var iconBitmap: Bitmap? = null
        private set

    fun <T> withTitleHidden(block: () -> T): T {
        val titleAlpha = titleLabel.alpha
        titleLabel.alpha = 0f
        try {
            return block()
        } finally {
            titleLabel.alpha = titleAlpha
        }
    }

    // Title at its start, without fades, as wide as the bar allows with actions hidden.
    fun titleSnapshot(): TitleSnapshot? {
        val layout = titleLabel.layout ?: return null
        if (titleLabel.width <= 0 || titleLabel.height <= 0) return null
        val paddings = titleLabel.totalPaddingLeft + titleLabel.totalPaddingRight
        val textWidth = layout.getLineWidth(0) + paddings
        val filledWidth = if (LocaleController.isRTL) {
            titleLabel.right - 16.dp
        } else {
            width - 16.dp - titleLabel.left
        }.coerceAtLeast(titleLabel.width)
        val snapshotWidth = min(textWidth.roundToInt(), filledWidth)
        val label = WLabel(context).apply {
            typeface = titleLabel.typeface
            setTextSize(TypedValue.COMPLEX_UNIT_PX, titleLabel.textSize)
            setTextColor(titleLabel.currentTextColor)
            gravity = titleLabel.gravity
            setSingleLine()
            setPadding(
                titleLabel.paddingLeft,
                titleLabel.paddingTop,
                titleLabel.paddingRight,
                titleLabel.paddingBottom
            )
            text = titleLabel.text
            layoutParams = LayoutParams(snapshotWidth, titleLabel.height)
            measure(
                MeasureSpec.makeMeasureSpec(snapshotWidth, MeasureSpec.EXACTLY),
                MeasureSpec.makeMeasureSpec(titleLabel.height, MeasureSpec.EXACTLY)
            )
            layout(0, 0, snapshotWidth, titleLabel.height)
            // Detached labels don't scroll RTL text into view.
            if (LocaleController.isRTL) {
                val lineRight = this.layout?.getLineRight(0) ?: 0f
                scrollTo(
                    (lineRight + totalPaddingLeft + totalPaddingRight).roundToInt() - snapshotWidth,
                    0
                )
            }
        }
        val bitmap = createBitmap(snapshotWidth, titleLabel.height)
        label.draw(Canvas(bitmap).apply { translate(-label.scrollX.toFloat(), 0f) })
        return TitleSnapshot(
            bitmap = bitmap,
            left = titleLabel.left + titleLabel.translationX,
            top = titleLabel.top + titleLabel.translationY,
            width = titleLabel.width.toFloat(),
            filledWidth = filledWidth.toFloat(),
            textWidth = textWidth,
            fadeLength = titleLabel.horizontalFadingEdgeLength.toFloat()
        )
    }

    fun <T> withActionsHidden(block: () -> T): T {
        val moreAlpha = moreButton.alpha
        val minimizeAlpha = minimizeButton.alpha
        moreButton.alpha = 0f
        minimizeButton.alpha = 0f
        try {
            return block()
        } finally {
            moreButton.alpha = moreAlpha
            minimizeButton.alpha = minimizeAlpha
        }
    }

    fun iconSnapshot(): Bitmap? =
        iconBitmap ?: iconView.takeIf { iconUrl != null && it.width > 0 }?.asImage()

    val displayTitle: String?
        get() = (titleBeforeStack ?: titleLabel.text)?.toString()?.trim()?.takeIf {
            it.isNotEmpty()
        }

    fun setIconUrl(url: String) {
        iconUrl = url
        iconBitmap = null
        iconView.set(Content.ofUrl(url))
    }

    fun setIconBitmap(bitmap: Bitmap?) {
        iconBitmap = bitmap
        iconUrl = null
        iconView.setImageBitmap(bitmap)
    }
}

data class TitleSnapshot(
    val bitmap: Bitmap,
    val left: Float,
    val top: Float,
    val width: Float,
    val filledWidth: Float,
    val textWidth: Float,
    val fadeLength: Float
)
