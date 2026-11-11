package org.mytonwallet.app_air.uiagent.viewControllers.news

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
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.core.view.isGone
import androidx.core.view.updateLayoutParams
import com.google.android.material.progressindicator.CircularProgressIndicator
import kotlin.math.min
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.mytonwallet.app_air.icons.R
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.adaptiveFontSize
import org.mytonwallet.app_air.uicomponents.widgets.WButton
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.getDrawableCompat
import org.mytonwallet.app_air.walletcore.models.MBridgeError
import org.mytonwallet.app_air.walletcore.pushNotifications.AgentNewsNotificationMode

/**
 * The digest's hour and the choice of MyPulse notifications, in a bottom sheet as tall as its content under the
 * header the app's sheets have, with Done at its foot. A change made before the sheet closes is still applied.
 */
@SuppressLint("ViewConstructor")
class AgentDigestSettingsSheetVC private constructor(context: Context) : WViewController(context) {
    @Suppress("PropertyName")
    override val TAG = "AgentDigestSettingsSheet"

    override val shouldDisplayTopBar = false

    override val wrapsContentInCenteredWindow = true

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val model = AgentDigestSettingsModel(AgentDigestNotificationSettings.Shared) {
        if (!isDestroyed) showError(MBridgeError.Type.UNEXPECTED_ERROR)
    }

    private val textLabel = WLabel(context).apply {
        setStyle(TEXT_SIZE)
        setLineHeight(TEXT_LINE_HEIGHT)
        text = LocaleController.getString("\$agent_digest_settings_text")
    }

    // The chosen hour on the pill a settings value that opens a choice has, with its arrows
    private val hourArrows = context.getDrawableCompat(R.drawable.ic_arrows_18)
    private val hourValueView = WLabel(context).apply {
        setStyle(adaptiveFontSize(), WFont.Medium)
        setSingleLine()
        gravity = android.view.Gravity.CENTER_VERTICAL
        setPaddingRelative(HOUR_PILL_START.dp, 0, HOUR_PILL_END.dp, 0)
        compoundDrawablePadding = HOUR_ARROWS_GAP.dp
        setCompoundDrawablesRelativeWithIntrinsicBounds(null, null, hourArrows, null)
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
        addView(hourValueView, ConstraintLayout.LayoutParams(WRAP_CONTENT, HOUR_PILL_HEIGHT.dp))
        setConstraints {
            toStart(hourTitleLabel, ROW_INSET.toFloat())
            endToStart(hourTitleLabel, hourValueView, ROW_GAP.toFloat())
            toCenterY(hourTitleLabel)
            toEnd(hourValueView, ROW_INSET.toFloat())
            toCenterY(hourValueView)
        }
        setOnClickListener { showHourMenu() }
    }
    private val timeZoneLabel = makeFootnote(LocaleController.getString("\$agent_digest_time_zone"))
    private val notificationsHeader = WLabel(context).apply {
        setStyle(SECTION_HEADER_TEXT_SIZE, WFont.Medium)
        text = LocaleController.getString("Notifications")
        setPaddingRelative(
            ROW_INSET.dp,
            SECTION_HEADER_TOP.dp,
            ROW_INSET.dp,
            SECTION_HEADER_BOTTOM.dp
        )
    }
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
    private val hourSection = makeSection(hourRow)
    private val notificationsSection =
        makeSection(notificationsHeader, *modeRows.values.toTypedArray())
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
        addView(textLabel, footnoteParams(bottomMargin = ViewConstants.GAP.dp + TEXT_GAP.dp))
        addView(hourSection, sectionParams())
        addView(timeZoneLabel, footnoteParams(topMargin = FOOTNOTE_GAP.dp))
        addView(notificationsSection, sectionParams(topMargin = ViewConstants.GAP.dp + TEXT_GAP.dp))
        addView(permissionSection, sectionParams(topMargin = ViewConstants.GAP.dp))
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
        setNavTitle(LocaleController.getString("\$agent_digest_settings_title"))
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
        }
        model.onChange = ::updateViews
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
        textLabel.setTextColor(WColor.SecondaryText)
        timeZoneLabel.setTextColor(WColor.SecondaryText)
        hourTitleLabel.setTextColor(WColor.PrimaryText)
        hourValueView.setTextColor(WColor.PrimaryText)
        hourValueView.setBackgroundColor(WColor.TrinaryBackground.color, HOUR_PILL_HEIGHT.dp / 2f)
        hourArrows?.setTint(WColor.SecondaryText.color)
        notificationsHeader.setTextColor(WColor.Tint)
        permissionTitleLabel.setTextColor(WColor.PrimaryText)
        enableLabel.setTextColor(WColor.Tint)
        modeRows.values.forEach(ModeRow::updateTheme)
        doneButton.updateTheme()
    }

    override fun onDestroy() {
        model.onChange = null
        scope.cancel()
        super.onDestroy()
    }

    private fun updateViews() {
        val hour = AgentDigestSettingsModel.formatHour(model.digestHour)
        hourValueView.text = hour
        hourRow.contentDescription = "${LocaleController.getString("\$agent_digest_time")}, $hour"
        hourRow.isEnabled = !model.isApplyingHour
        modeRows.forEach { (mode, row) ->
            row.configure(
                hint = model.hint(mode),
                isSelected = model.mode == mode,
                isPending = model.pendingMode == mode,
                isEnabled = model.pendingMode == null
            )
        }
        permissionSection.isGone = !model.isPermissionDenied
    }

    /** The 24 hours, the current one marked; a pick while another hour is applied is ignored */
    private fun showHourMenu() {
        if (model.isApplyingHour) return
        WMenuPopup.present(
            hourValueView,
            AgentDigestSettingsModel.HOURS.map { hour ->
                WMenuPopup.Item(
                    WMenuPopup.Item.Config.SelectableItem(
                        title = AgentDigestSettingsModel.formatHour(hour),
                        subtitle = null,
                        isSelected = hour == model.digestHour
                    )
                ) { applyChange { model.selectHour(hour) } }
            },
            popupWidth = WRAP_CONTENT,
            positioning = WMenuPopup.Positioning.BELOW,
            windowBackgroundStyle = WMenuPopup.BackgroundStyle.Cutout.fromView(
                hourValueView,
                roundRadius = HOUR_CUTOUT_RADIUS.dp
            )
        )
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
    private fun footnoteParams(topMargin: Int = 0, bottomMargin: Int = 0) =
        LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply {
            marginStart = FOOTNOTE_INSET.dp
            marginEnd = FOOTNOTE_INSET.dp
            this.topMargin = topMargin
            this.bottomMargin = bottomMargin
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

    /** A notification choice: the app's radio, its title and hint, and a spinner in the radio's place while applied */
    @SuppressLint("ViewConstructor")
    private class ModeRow(context: Context, title: String) :
        WView(context),
        WThemedView {
        private val ripple = WRippleDrawable.create(0f)
        private val radioView = ImageView(context).apply {
            id = generateViewId()
            importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
        }
        private val spinner = CircularProgressIndicator(context).apply {
            id = generateViewId()
            isIndeterminate = true
            indicatorSize = SPINNER_SIZE.dp
            trackThickness = SPINNER_THICKNESS.dp
            isGone = true
        }
        private val titleLabel = WLabel(context).apply {
            setStyle(adaptiveFontSize(), WFont.Medium)
            text = title
        }
        private val hintLabel = WLabel(context).apply {
            setStyle(FOOTNOTE_TEXT_SIZE)
            setLineHeight(FOOTNOTE_LINE_HEIGHT)
        }

        init {
            minimumHeight = MODE_ROW_HEIGHT.dp
            background = ripple
            importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES
            isFocusable = true
            addView(radioView, LayoutParams(RADIO_BOX.dp, RADIO_BOX.dp))
            addView(spinner, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
            addView(titleLabel, LayoutParams(0, WRAP_CONTENT))
            addView(hintLabel, LayoutParams(0, WRAP_CONTENT))
            setConstraints {
                toStart(radioView, RADIO_START.toFloat())
                toCenterY(radioView)
                centerXToCenterX(spinner, radioView)
                centerYToCenterY(spinner, radioView)
                toStart(titleLabel, MODE_TEXT_START.toFloat())
                toEnd(titleLabel, ROW_INSET.toFloat())
                toTop(titleLabel, MODE_TEXT_TOP.toFloat())
                topToBottom(hintLabel, titleLabel, MODE_HINT_GAP.toFloat())
                toStart(hintLabel, MODE_TEXT_START.toFloat())
                toEnd(hintLabel, ROW_INSET.toFloat())
                toBottom(hintLabel, MODE_TEXT_TOP.toFloat())
            }
            updateTheme()
        }

        fun configure(hint: String, isSelected: Boolean, isPending: Boolean, isEnabled: Boolean) {
            // TalkBack reads the current choice as selected
            this.isSelected = isSelected
            hintLabel.text = hint
            radioView.isGone = isPending
            spinner.isGone = !isPending
            this.isEnabled = isEnabled
            contentDescription = "${titleLabel.text}, $hint"
            updateRadio()
        }

        override fun updateTheme() {
            ripple.backgroundColor = WColor.Background.color
            ripple.rippleColor = WColor.SecondaryBackground.color
            titleLabel.setTextColor(WColor.PrimaryText)
            hintLabel.setTextColor(WColor.SecondaryText)
            spinner.setIndicatorColor(WColor.Tint.color)
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
        private const val TEXT_SIZE = 15f
        private const val TEXT_LINE_HEIGHT = 20f
        private const val TEXT_GAP = 4
        private const val FOOTNOTE_TEXT_SIZE = 13f
        private const val FOOTNOTE_LINE_HEIGHT = 18f
        private const val FOOTNOTE_INSET = 16
        private const val FOOTNOTE_GAP = 8
        private const val ROW_HEIGHT = 50
        private const val ROW_INSET = 20
        private const val ROW_GAP = 16
        private const val SECTION_HEADER_TEXT_SIZE = 14f
        private const val SECTION_HEADER_TOP = 16
        private const val SECTION_HEADER_BOTTOM = 4
        private const val PERMISSION_TEXT_INSET = 14
        private const val HOUR_CUTOUT_RADIUS = 40f
        private const val HOUR_PILL_HEIGHT = 36
        private const val HOUR_PILL_START = 12
        private const val HOUR_PILL_END = 6
        private const val HOUR_ARROWS_GAP = 4
        private const val BUTTON_HEIGHT = 50
        private const val BUTTON_MARGIN = 16

        // A choice as the app's selection rows show one: the radio in a 40 dp box 12 dp in, the text 64 dp in
        private const val MODE_ROW_HEIGHT = 60
        private const val RADIO_BOX = 40
        private const val RADIO_START = 12
        private const val MODE_TEXT_START = 64
        private const val MODE_TEXT_TOP = 10
        private const val MODE_HINT_GAP = 2
        private const val SPINNER_SIZE = 20
        private const val SPINNER_THICKNESS = 2

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
