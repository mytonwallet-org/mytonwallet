package org.mytonwallet.app_air.uiagent.viewControllers.news

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.core.animation.doOnEnd
import androidx.core.view.isGone
import androidx.core.view.updateLayoutParams
import kotlin.math.min
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.mytonwallet.app_air.icons.R
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.CubicBezierInterpolator
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.adaptiveFontSize
import org.mytonwallet.app_air.uicomponents.widgets.WButton
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.DEBUG_MODE
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.getDrawableCompat
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcore.models.MBridgeError
import org.mytonwallet.app_air.walletcore.pushNotifications.AgentNewsNotificationMode

/**
 * The choice of MyPulse notifications and the digest's time, in a bottom sheet as tall as its content under the
 * header the app's sheets have, with Done at its foot. The time's row opens a wheel of hours and minutes under it, as
 * on iOS. A change made before the sheet closes is still applied.
 */
@SuppressLint("ViewConstructor")
class AgentDigestSettingsSheetVC private constructor(context: Context) : WViewController(context) {
    @Suppress("PropertyName")
    override val TAG = "AgentDigestSettingsSheet"

    override val shouldDisplayTopBar = false

    override val wrapsContentInCenteredWindow = true

    // As tall as its content, which the sheet follows as the time's wheel opens and closes
    override val isExpandable = false

    override fun getModalHalfExpandedHeight(): Int {
        val width = navigationController?.width?.takeIf { it > 0 } ?: view.width
        view.measure(
            View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED)
        )
        val windowHeight = window?.windowView?.height?.takeIf { it > 0 }
            ?: return view.measuredHeight
        return min(view.measuredHeight, windowHeight)
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val model = AgentDigestSettingsModel(
        AgentDigestNotificationSettings.Shared,
        AgentDigestSettingsModel.sharedPendingState
    )
    private val updateModelViews: () -> Unit = ::updateViews

    // The chosen time, in the accent while its wheel is open
    private val hourValueView = WLabel(context).apply {
        setStyle(adaptiveFontSize())
        setSingleLine()
        importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
    }
    private val hourTitleLabel = WLabel(context).apply {
        setStyle(adaptiveFontSize())
        text = LocaleController.getString("\$agent_digest_time")
    }
    private val hourRipple = WRippleDrawable.create(0f)
    private val hourRow = WView(context).apply {
        // `ConstraintLayout` measures with its own minimum height, not the view's
        minHeight = ROW_HEIGHT.dp
        background = hourRipple
        addView(hourTitleLabel, ConstraintLayout.LayoutParams(0, WRAP_CONTENT))
        addView(hourValueView, ConstraintLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        setConstraints {
            toStart(hourTitleLabel, ROW_INSET.toFloat())
            endToStart(hourTitleLabel, hourValueView, ROW_GAP.toFloat())
            toCenterY(hourTitleLabel)
            toEnd(hourValueView, ROW_INSET.toFloat())
            toCenterY(hourValueView)
        }
        setOnClickListener { toggleHourWheel() }
    }
    private val hourWheel = AgentHourWheelView(context).apply {
        onTimeSelected = { time -> applyChange { model.selectTime(time) } }
    }

    // Holds the wheel at its full height while it opens and closes, the section growing with it
    private val hourWheelContainer = FrameLayout(context).apply {
        id = View.generateViewId()
        clipChildren = true
        isGone = true
        addView(hourWheel, FrameLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
    }
    private var isHourWheelShown = false
    private var hourWheelAnimator: ValueAnimator? = null
    private val hourHintLabel = makeFootnote(LocaleController.getString("\$agent_digest_time_hint"))
    private val modeRows = AgentDigestSettingsModel.MODES.associateWith { mode ->
        ModeRow(context, AgentDigestSettingsModel.title(mode)).apply {
            setOnClickListener { select(mode) }
        }
    }
    private val permissionTitleLabel = WLabel(context).apply {
        setStyle(adaptiveFontSize(), WFont.Medium)
        text = LocaleController.getString("Notifications are disabled")
        setPaddingRelative(
            ROW_INSET.dp,
            PERMISSION_TEXT_INSET.dp,
            ROW_INSET.dp,
            PERMISSION_TEXT_INSET.dp
        )
    }
    private val enableRipple = WRippleDrawable.create(0f)
    private val enableLabel = WLabel(context).apply {
        setStyle(adaptiveFontSize())
        text = LocaleController.getString("Enable in Settings")
        minimumHeight = ROW_HEIGHT.dp
        gravity = android.view.Gravity.CENTER_VERTICAL
        setPaddingRelative(ROW_INSET.dp, 0, ROW_INSET.dp, 0)
        background = enableRipple
        setOnClickListener { openNotificationSettings() }
    }
    private val hourSection = makeSection(hourRow, hourWheelContainer)
    private val notificationsSection = makeSection(*modeRows.values.toTypedArray())
    private val permissionSection = makeSection(permissionTitleLabel, enableLabel).apply {
        isGone = true
    }
    private val columnView = LinearLayout(context).apply {
        id = View.generateViewId()
        orientation = LinearLayout.VERTICAL
        setPaddingRelative(
            ViewConstants.HORIZONTAL_PADDINGS.dp,
            CONTENT_TOP.dp,
            ViewConstants.HORIZONTAL_PADDINGS.dp,
            0
        )
        addView(notificationsSection, sectionParams())
        addView(permissionSection, sectionParams(topMargin = ViewConstants.GAP.dp))
        addView(hourSection, sectionParams(topMargin = ViewConstants.GAP.dp + SECTION_GAP.dp))
        addView(hourHintLabel, footnoteParams(topMargin = FOOTNOTE_GAP.dp))
    }
    private val scrollView = ScrollView(context).apply {
        id = View.generateViewId()
        isVerticalScrollBarEnabled = false
        overScrollMode = View.OVER_SCROLL_NEVER
        addView(columnView, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
    }
    private val doneButton = WButton(context, WButton.Type.PRIMARY).apply {
        text = LocaleController.getString("Done")
        setOnClickListener { window?.dismissLastNav() }
    }
    private val contentView = SheetContent(context).apply {
        addView(scrollView, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT, 1f))
        addView(
            doneButton,
            LinearLayout.LayoutParams(MATCH_PARENT, BUTTON_HEIGHT.dp).apply {
                setMargins(BUTTON_MARGIN.dp, BUTTON_MARGIN.dp, BUTTON_MARGIN.dp, BUTTON_MARGIN.dp)
            }
        )
    }

    override fun setupViews() {
        super.setupViews()
        setNavTitle(LocaleController.getString("Notifications"))
        setupNavBar(true)
        navigationBar?.addCloseButton()
        view.addView(
            contentView,
            ConstraintLayout.LayoutParams(
                ConstraintLayout.LayoutParams.MATCH_CONSTRAINT,
                ConstraintLayout.LayoutParams.WRAP_CONTENT
            )
        )
        view.setConstraints {
            navigationBar?.let { topToBottom(contentView, it) } ?: toTop(contentView)
            toCenterX(contentView)
            toBottom(contentView)
            // A centred window grows only up to its frame's limit, past which the content scrolls above Done
            constrainedHeight(contentView.id, true)
        }
        model.onChange = updateModelViews
        model.onError = {
            if (!isDestroyed) showError(MBridgeError.Type.UNEXPECTED_ERROR)
        }
        updateViews()
        updateTheme()
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        val bars = navigationController?.getSystemBars()
        doneButton.updateLayoutParams<LinearLayout.LayoutParams> {
            bottomMargin = BUTTON_MARGIN.dp + (bars?.bottom ?: 0)
        }
        // The sheet, its header included, stops short of the status bar, where the content scrolls
        val windowHeight = window?.windowView?.height ?: 0
        contentView.maxContentHeight = (
            windowHeight - (bars?.top ?: 0) - SHEET_TOP_GAP.dp - WNavigationBar.DEFAULT_HEIGHT.dp
            ).coerceAtLeast(0)
        view.setConstraints {
            toStartPx(contentView, systemBarStartInset)
            toEndPx(contentView, systemBarEndInset)
        }
    }

    override fun updateTheme() {
        super.updateTheme()
        view.setBackgroundColor(WColor.SecondaryBackground.color, ViewConstants.BLOCK_RADIUS.dp, 0f)
        listOf(hourSection, notificationsSection, permissionSection).forEach {
            it.setBackgroundColor(WColor.Background.color, ViewConstants.BLOCK_RADIUS.dp, true)
        }
        listOf(hourRipple, enableRipple).forEach {
            it.backgroundColor = WColor.Background.color
            it.rippleColor = WColor.SecondaryBackground.color
        }
        hourHintLabel.setTextColor(WColor.SecondaryText)
        hourTitleLabel.setTextColor(WColor.PrimaryText)
        updateHourValueColor()
        hourWheel.updateTheme()
        permissionTitleLabel.setTextColor(WColor.PrimaryText)
        enableLabel.setTextColor(WColor.Tint)
        modeRows.values.forEach(ModeRow::updateTheme)
        doneButton.updateTheme()
    }

    override fun viewWillDisappear() {
        super.viewWillDisappear()
        // The wheel settles at once, so the sheet going away isn't resized under its dismiss animation
        hourWheelAnimator?.end()
    }

    override fun onDestroy() {
        hourWheelAnimator?.let {
            hourWheelAnimator = null
            it.cancel()
        }
        if (model.onChange === updateModelViews) {
            model.onChange = null
            model.onError = null
        }
        scope.cancel()
        super.onDestroy()
    }

    private fun updateViews() {
        val time = AgentDigestSettingsModel.formatTime(model.digestTime)
        hourValueView.text = time
        hourRow.contentDescription = "${LocaleController.getString("\$agent_digest_time")}, $time"
        hourWheel.setTime(model.digestTime, animated = hourWheelContainer.isShown)
        modeRows.forEach { (mode, row) ->
            row.configure(hint = model.hint(mode), isSelected = model.mode == mode)
        }
        val isPermissionGone = !model.isPermissionDenied
        if (permissionSection.isGone != isPermissionGone) {
            permissionSection.isGone = isPermissionGone
            fitSheetToContent()
        }
    }

    /** Opens or closes the time's wheel under its row, the sheet growing or shrinking with it */
    private fun toggleHourWheel() {
        isHourWheelShown = !isHourWheelShown
        updateHourValueColor()
        hourRow.isSelected = isHourWheelShown
        val from = if (hourWheelContainer.isGone) 0 else hourWheelContainer.height
        hourWheelAnimator?.let {
            hourWheelAnimator = null
            it.cancel()
        }
        hourWheel.measure(
            View.MeasureSpec.makeMeasureSpec(hourSection.width, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED)
        )
        val fullHeight = hourWheel.measuredHeight
        val to = if (isHourWheelShown) fullHeight else 0
        hourWheelContainer.isGone = false
        fun setHeight(height: Int) {
            hourWheelContainer.updateLayoutParams<LinearLayout.LayoutParams> {
                this.height = height
            }
            fitSheetToContent()
        }
        val isSystemMotionOn = !DEBUG_MODE ||
            Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
            ValueAnimator.areAnimatorsEnabled()
        val canAnimate = WGlobalStorage.getAreAnimationsActive() && isSystemMotionOn
        if (!canAnimate) {
            setHeight(to)
            hourWheelContainer.isGone = !isHourWheelShown
            return
        }
        hourWheelAnimator = ValueAnimator.ofInt(from, to).apply {
            duration = AnimationConstants.QUICK_ANIMATION
            interpolator = CubicBezierInterpolator.EASE_BOTH
            addUpdateListener { setHeight(it.animatedValue as Int) }
            doOnEnd { animator ->
                if (hourWheelAnimator !== animator) return@doOnEnd
                hourWheelAnimator = null
                if (!isHourWheelShown) hourWheelContainer.isGone = true
            }
            start()
        }
    }

    /**
     * Fits the sheet to its content's height: a bottom sheet keeps its foot at the screen's, so the rows and Done move up
     * instead of down past the screen's edge, and a centred window stays centred
     */
    private fun fitSheetToContent() {
        // The sheet takes its first height as it is presented and keeps its last one as it goes away
        if (!view.isLaidOut || isDisappeared) return
        val navigation = navigationController?.takeIf { !it.isDismissed } ?: return
        when {
            navigation.isBottomSheet -> navigation.onBottomSheetHeightChanged()
            navigation.isCenteredWindow -> window?.relayoutCenteredWindow(navigation)
        }
    }

    private fun updateHourValueColor() {
        hourValueView.setTextColor(if (isHourWheelShown) WColor.Tint else WColor.SecondaryText)
    }

    private fun select(mode: AgentNewsNotificationMode) = applyChange { model.selectMode(mode) }

    // The settings finish applying a change the sheet asked for, also once it has closed and stopped showing it
    private fun applyChange(change: suspend () -> Unit) {
        scope.launch { withContext(NonCancellable) { change() } }
    }

    private fun openNotificationSettings() {
        val packageName = context.packageName
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
        } else {
            Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.fromParts("package", packageName, null)
            )
        }
        try {
            window?.startActivity(intent)
        } catch (_: ActivityNotFoundException) {
            window?.startActivity(
                Intent(
                    Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                    Uri.fromParts("package", packageName, null)
                )
            )
        }
    }

    private fun makeFootnote(text: String) = WLabel(context).apply {
        setStyle(FOOTNOTE_TEXT_SIZE)
        setLineHeight(FOOTNOTE_LINE_HEIGHT)
        this.text = text
    }

    /** The app's inset section: rows on a rounded block */
    private fun makeSection(vararg rows: View) = LinearLayout(context).apply {
        id = View.generateViewId()
        orientation = LinearLayout.VERTICAL
        rows.forEach { addView(it, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT)) }
    }

    private fun sectionParams(topMargin: Int = 0) =
        LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply { this.topMargin = topMargin }

    // Footnotes stand as the settings' do, a little inside their sections
    private fun footnoteParams(topMargin: Int = 0) =
        LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply {
            marginStart = FOOTNOTE_INSET.dp
            marginEnd = FOOTNOTE_INSET.dp
            this.topMargin = topMargin
        }

    /** The sheet's text over Done, as tall as it up to [maxContentHeight], past which the text scrolls */
    private class SheetContent(context: Context) : LinearLayout(context) {
        var maxContentHeight = 0
            set(value) {
                if (field == value) return
                field = value
                requestLayout()
            }

        init {
            id = generateViewId()
            orientation = VERTICAL
        }

        override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
            val limit = maxContentHeight
            if (limit <= 0) return super.onMeasure(widthMeasureSpec, heightMeasureSpec)
            val available = if (MeasureSpec.getMode(heightMeasureSpec) == MeasureSpec.UNSPECIFIED) {
                limit
            } else {
                min(limit, MeasureSpec.getSize(heightMeasureSpec))
            }
            super.onMeasure(
                widthMeasureSpec,
                MeasureSpec.makeMeasureSpec(available, MeasureSpec.AT_MOST)
            )
        }
    }

    /** A notification choice: the app's radio, which takes the choice once tapped, its title and its hint */
    @SuppressLint("ViewConstructor")
    private class ModeRow(context: Context, title: String) :
        WView(context),
        WThemedView {
        private val ripple = WRippleDrawable.create(0f)
        private val radioView = ImageView(context).apply {
            id = generateViewId()
            importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
        }
        private val titleLabel = WLabel(context).apply {
            setStyle(adaptiveFontSize(), WFont.Medium)
            text = title
        }
        private val hintLabel = WLabel(context).apply {
            setStyle(FOOTNOTE_TEXT_SIZE)
            setLineHeight(FOOTNOTE_LINE_HEIGHT)
            setPadding(0, MODE_HINT_GAP.dp, 0, 0)
        }

        // The title alone, or over its hint, in the middle of the row
        private val textColumn = LinearLayout(context).apply {
            id = generateViewId()
            orientation = LinearLayout.VERTICAL
            addView(titleLabel, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
            addView(hintLabel, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        }

        init {
            // `ConstraintLayout` measures with its own minimum height, not the view's
            minHeight = ROW_HEIGHT.dp
            background = ripple
            importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES
            isFocusable = true
            addView(radioView, LayoutParams(RADIO_BOX.dp, RADIO_BOX.dp))
            addView(textColumn, LayoutParams(0, WRAP_CONTENT))
            setConstraints {
                toStart(radioView, RADIO_START.toFloat())
                toCenterY(radioView)
                toStart(textColumn, MODE_TEXT_START.toFloat())
                toEnd(textColumn, ROW_INSET.toFloat())
                toCenterY(textColumn, MODE_TEXT_TOP.toFloat())
            }
            updateTheme()
        }

        fun configure(hint: String?, isSelected: Boolean) {
            // TalkBack reads the current choice as selected
            this.isSelected = isSelected
            hintLabel.text = hint
            hintLabel.isGone = hint == null
            contentDescription = listOfNotNull(titleLabel.text, hint).joinToString(", ")
            updateRadio()
        }

        override fun updateTheme() {
            ripple.backgroundColor = WColor.Background.color
            ripple.rippleColor = WColor.SecondaryBackground.color
            titleLabel.setTextColor(WColor.PrimaryText)
            hintLabel.setTextColor(WColor.SecondaryText)
            updateRadio()
        }

        private fun updateRadio() {
            radioView.setImageDrawable(
                context.getDrawableCompat(
                    if (isSelected) R.drawable.ic_radio_fill else R.drawable.ic_radio
                )?.apply {
                    setTint(if (isSelected) WColor.Tint.color else WColor.Separator.color)
                }
            )
        }
    }

    companion object {
        // The gap the window keeps above a sheet as tall as it, in dp
        private const val SHEET_TOP_GAP = 20

        // In dp and sp: the settings' sections, rows and footnotes
        private const val CONTENT_TOP = 4
        private const val SECTION_GAP = 4
        private const val FOOTNOTE_TEXT_SIZE = 13f
        private const val FOOTNOTE_LINE_HEIGHT = 18f
        private const val FOOTNOTE_INSET = 16
        private const val FOOTNOTE_GAP = 8
        private const val ROW_HEIGHT = 50
        private const val ROW_INSET = 20
        private const val ROW_GAP = 16
        private const val PERMISSION_TEXT_INSET = 14
        private const val BUTTON_HEIGHT = 50
        private const val BUTTON_MARGIN = 16

        // A choice as the app's selection rows show one: the radio in a 40 dp box 12 dp in, the text 64 dp in
        private const val RADIO_BOX = 40
        private const val RADIO_START = 12
        private const val MODE_TEXT_START = 64
        private const val MODE_TEXT_TOP = 10
        private const val MODE_HINT_GAP = 2

        /** Shows the sheet over [from]'s window, once; nothing shows when [from] has no window */
        fun present(from: WViewController) {
            val window = from.window ?: return
            if (window.navigationControllers.lastOrNull()?.viewControllers?.lastOrNull()
                    is AgentDigestSettingsSheetVC
            ) {
                return
            }
            val navigation = WNavigationController(
                window,
                WNavigationController.PresentationConfig(
                    style = WNavigationController.PresentationStyle.BottomSheet
                )
            )
            navigation.setRoot(AgentDigestSettingsSheetVC(from.context))
            window.present(navigation)
        }
    }
}
