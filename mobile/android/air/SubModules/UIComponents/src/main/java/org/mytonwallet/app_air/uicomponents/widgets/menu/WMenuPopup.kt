package org.mytonwallet.app_air.uicomponents.widgets.menu

import android.graphics.Path
import android.graphics.drawable.Drawable
import android.os.Build
import android.view.View
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.FrameLayout
import org.mytonwallet.app_air.uicomponents.extensions.atMost
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.getLocationInWindow
import org.mytonwallet.app_air.uicomponents.extensions.unspecified
import org.mytonwallet.app_air.uicomponents.helpers.PopupHelpers
import org.mytonwallet.app_air.uicomponents.widgets.INavigationPopup
import org.mytonwallet.app_air.uicomponents.widgets.cancelAncestorTouches
import org.mytonwallet.app_air.uicomponents.widgets.frameAsPath
import org.mytonwallet.app_air.uicomponents.widgets.lockView
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup.Item.Config.Icon
import org.mytonwallet.app_air.uicomponents.widgets.unlockView
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.theme.colorForTheme
import org.mytonwallet.app_air.walletbasecontext.utils.ApplicationContextHolder
import org.mytonwallet.app_air.walletbasecontext.utils.Vec2i
import org.mytonwallet.app_air.walletbasecontext.utils.x
import org.mytonwallet.app_air.walletbasecontext.utils.y

class WMenuPopup {
    enum class Positioning {
        ABOVE,
        ALIGNED,
        BELOW
    }

    enum class SubmenuTransition {
        PAGE,
        EXPAND_FROM_ITEM
    }

    enum class RowStyle {
        DEFAULT,
        WALLET
    }

    data class Item(
        val config: Config,
        var hasSeparator: Boolean = false,
        val shouldKeepOpen: Boolean = false,
        val onTap: (() -> Unit)? = null
    ) {
        constructor(
            icon: Int?,
            title: String,
            hasSeparator: Boolean = false,
            onTap: (() -> Unit)? = null
        ) : this(
            Config.Item(
                icon?.let { Icon(icon, tintColor = WColor.SecondaryText) },
                title
            ),
            hasSeparator = hasSeparator,
            onTap = onTap
        )

        // Stable resource id of the item view, for UI automation
        var testViewId: Int? = null

        sealed class Config {
            data object Back : Config()
            data class Item(
                val icon: Icon?,
                val title: CharSequence,
                val titleColor: Int? = null,
                val subtitle: CharSequence? = null,
                val isSubItem: Boolean = false,
                val subItems: List<WMenuPopup.Item>? = null,
                val trailingView: View? = null,
                val textMargin: Int? = null,
                val trailingViewProvider: (() -> View)? = null,
                val submenuTransition: SubmenuTransition = SubmenuTransition.PAGE,
                val rowStyle: RowStyle = RowStyle.DEFAULT
            ) : Config()

            data class SelectableItem(
                val title: CharSequence,
                val subtitle: CharSequence?,
                val isSelected: Boolean
            ) : Config()

            data class CustomView(val customView: FrameLayout, val height: Int = 56.dp) : Config()

            data class Icon(
                val iconResId: Int?,
                val tintColor: WColor? = null,
                val iconSize: Int? = null,
                val iconMargin: Int? = null,
                val drawable: Drawable? = null,
                /**
                 * A Lottie animation whose last frame is the icon, played each time the item
                 * becomes active. With animations off, the item shows [iconResId] instead.
                 */
                val animationResId: Int? = null
            )
        }

        fun getIcon(): Int? = when (config) {
            is Config.Back -> {
                org.mytonwallet.app_air.icons.R.drawable.ic_menu_back
            }

            is Config.Item -> {
                config.icon?.iconResId
            }

            is Config.SelectableItem -> {
                if (config.isSelected) {
                    org.mytonwallet.app_air.icons.R.drawable.ic_radio_fill
                } else {
                    null
                }
            }

            else -> {
                null
            }
        }

        /** In the theme [isDark] picks, or the app's */
        fun getIconTint(isDark: Boolean? = null): Int? = when (config) {
            is Config.Item -> {
                config.icon?.tintColor?.colorForTheme(isDark)
            }

            is Config.SelectableItem -> {
                WColor.Tint.colorForTheme(isDark)
            }

            Config.Back -> {
                WColor.PrimaryLightText.colorForTheme(isDark)
            }

            else -> {
                WColor.SecondaryText.colorForTheme(isDark)
            }
        }

        fun getIconDrawable(): Drawable? = when (config) {
            is Config.Item -> config.icon?.drawable
            else -> null
        }

        fun getIconAnimation(): Int? = (config as? Config.Item)?.icon?.animationResId

        fun getIconSize(): Int? = when (config) {
            is Config.Item -> {
                config.icon?.iconSize
            }

            else -> {
                null
            }
        }

        fun getIconMargin(): Int? = when (config) {
            is Config.Item -> {
                config.icon?.iconMargin
            }

            else -> {
                null
            }
        }

        fun getTextMargin(): Int? = when (config) {
            is Config.Item -> {
                config.textMargin
            }

            else -> {
                null
            }
        }

        fun getRowStyle(): RowStyle = (config as? Config.Item)?.rowStyle ?: RowStyle.DEFAULT

        fun getTitle(): CharSequence? = when (config) {
            is Config.Back -> {
                LocaleController.getString("Back")
            }

            is Config.Item -> {
                config.title
            }

            is Config.SelectableItem -> {
                config.title
            }

            else -> {
                null
            }
        }

        fun getTitleColor(): Int? = when (config) {
            is Config.Item -> {
                config.titleColor
            }

            else ->
                null
        }

        fun getSubTitle(): CharSequence? = when (config) {
            is Config.Item -> {
                config.subtitle
            }

            is Config.SelectableItem -> {
                config.subtitle
            }

            else -> {
                null
            }
        }

        fun getSubItems(): List<Item>? = when (config) {
            is Config.Back -> {
                null
            }

            is Config.Item -> {
                config.subItems
            }

            is Config.SelectableItem -> {
                null
            }

            else -> {
                null
            }
        }

        fun getSubmenuTransition(): SubmenuTransition = when (config) {
            is Config.Item -> config.submenuTransition
            else -> SubmenuTransition.PAGE
        }

        fun getIsSubItem(): Boolean = when (config) {
            is Config.Back -> {
                false
            }

            is Config.Item -> {
                config.isSubItem
            }

            is Config.SelectableItem -> {
                false
            }

            else -> {
                false
            }
        }
    }

    companion object {
        /** A menu surface's elevation: lower over a dimmed or blurred window, which already sets it apart */
        fun surfaceElevation(isOverDim: Boolean): Float = (if (isOverDim) 2f else 4f).dp

        /** Gives [view] the colours of a menu surface's shadow */
        fun applySurfaceShadowColors(view: View) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                view.outlineAmbientShadowColor = WColor.PopupAmbientShadow.color
                view.outlineSpotShadowColor = WColor.PopupSpotShadow.color
            }
        }

        fun present(
            view: View,
            items: List<Item>,
            popupWidth: Int = WRAP_CONTENT,
            xOffset: Int = 0,
            yOffset: Int = 0,
            positioning: Positioning,
            /**
             * With [Positioning.BELOW]: when the menu has no room below [view] but has room above it, it opens above,
             * as [Positioning.ABOVE] with this offset. A negative one keeps it clear of something over [view].
             */
            aboveFallbackYOffset: Int? = null,
            centerHorizontally: Boolean = false,
            /** Lines the menu up with [view]'s trailing edge, in either layout direction */
            isAlignedToEnd: Boolean = false,
            windowBackgroundStyle: BackgroundStyle =
                BackgroundStyle.Cutout.fromView(view, roundRadius = 16f.dp),
            backdropStyle: BackdropStyle = BackdropStyle.Transparent,
            usePillShadow: Boolean = false,
            onWillDismiss: (() -> Unit)? = null,
            onDidDismiss: (() -> Unit)? = null,
            displayProgressListener: ((progress: Float) -> Unit)? = null,
            cancelsAncestorTouches: Boolean = true,
            /**
             * Places the menu itself: given its measured width and height, the window position of its top-left corner.
             * It then opens downward from there, and [positioning] and the offsets don't apply.
             */
            placement: ((width: Int, height: Int) -> Vec2i)? = null,
            /** Morphs the root menu from [view]; closing root leaf actions run after the source is restored */
            shouldMorphFromSource: Boolean = false,
            /** Colors the menu in the dark (true) or light (false) theme whatever the app's, as over a dark screen */
            themeIsDark: Boolean? = null,
            /** Lets a finger slide across the root menu's items, choosing the one it lifts over */
            isSlideSelectionEnabled: Boolean = false,
            /**
             * Lets a held item be dragged to another place. Called with the item's old and new
             * position on each step, while the finger is still down
             */
            onReorder: ((fromPosition: Int, toPosition: Int) -> Unit)? = null
        ): INavigationPopup {
            if (cancelsAncestorTouches) view.cancelAncestorTouches()
            view.lockView()

            lateinit var popupWindow: WNavigationPopup
            var selectedAction: (() -> Unit)? = null
            val presentedItems = if (shouldMorphFromSource) {
                items.map { item ->
                    val action = item.onTap
                    if (action == null || item.shouldKeepOpen ||
                        !item.getSubItems().isNullOrEmpty()
                    ) {
                        item
                    } else {
                        item.copy(onTap = {
                            if (selectedAction == null) selectedAction = action
                        }).also { it.testViewId = item.testViewId }
                    }
                }
            } else {
                items
            }

            val initialPopupView = WMenuPopupView(
                view.context,
                presentedItems,
                onWillDismiss = onWillDismiss,
                onDismiss = {
                    popupWindow.dismiss()
                },
                verticalContentPadding = if (shouldMorphFromSource) 4.dp else 0,
                themeIsDark = themeIsDark,
                isSlideSelectionEnabled = isSlideSelectionEnabled,
                onReorder = onReorder
            )

            popupWindow =
                WNavigationPopup(
                    initialPopupView,
                    popupWidth,
                    windowBackgroundStyle,
                    backdropStyle,
                    usePillShadow,
                    morphSource = view.takeIf { shouldMorphFromSource }
                ).apply {
                    setOnDismissListener {
                        view.post {
                            view.unlockView()
                        }
                        val action = selectedAction
                        selectedAction = null
                        onDidDismiss?.invoke()
                        if (view.isAttachedToWindow) action?.invoke()
                    }
                    displayProgressListener?.let { setDisplayProgressListener(it) }
                }

            val location = view.getLocationInWindow()
            val screenWidth = ApplicationContextHolder.screenWidth
            val isRtl = view.layoutDirection == View.LAYOUT_DIRECTION_RTL
            val popupMeasuredWidth = if (popupWidth == WRAP_CONTENT) {
                initialPopupView.measure(screenWidth.atMost, 0.unspecified)
                initialPopupView.measuredWidth
            } else {
                popupWidth
            }
            val offset = xOffset + when {
                centerHorizontally -> (view.width - popupMeasuredWidth) / 2
                isAlignedToEnd -> if (isRtl) 0 else view.width - popupMeasuredWidth
                isRtl && xOffset == 0 -> view.width - popupMeasuredWidth
                else -> 0
            }

            placement?.let { place ->
                initialPopupView.measure(screenWidth.atMost, 0.unspecified)
                val position = place(popupMeasuredWidth, initialPopupView.measuredHeight)
                popupWindow.showAtLocation(x = position.x, y = position.y, fromTop = true)
                return popupWindow
            }

            val belowY = location.y + yOffset + (view.height + 8.dp)
            val opensAbove = positioning == Positioning.ABOVE || (
                aboveFallbackYOffset != null &&
                    positioning == Positioning.BELOW &&
                    hasRoomOnlyAbove(initialPopupView, belowY, location.y + aboveFallbackYOffset)
                )
            val y = when {
                opensAbove -> {
                    initialPopupView.measure(screenWidth.atMost, 0.unspecified)
                    val aboveYOffset = if (positioning ==
                        Positioning.ABOVE
                    ) {
                        yOffset
                    } else {
                        aboveFallbackYOffset!!
                    }
                    location.y + aboveYOffset - (initialPopupView.measuredHeight + 8.dp)
                }

                positioning == Positioning.ALIGNED -> {
                    location.y + yOffset
                }

                else -> {
                    belowY
                }
            }

            popupWindow.showAtLocation(
                x = location.x + offset,
                y = y,
                fromTop = !opensAbove
            )
            return popupWindow
        }

        /** Whether the menu overflows the popup host's content area from [belowY] but fits ending above [aboveBottom] */
        private fun hasRoomOnlyAbove(
            popupView: WMenuPopupView,
            belowY: Int,
            aboveBottom: Int
        ): Boolean {
            val host = PopupHelpers.popupHost ?: return false
            popupView.measure(ApplicationContextHolder.screenWidth.atMost, 0.unspecified)
            val height = popupView.measuredHeight
            val hostTop = host.getLocationInWindow().y
            val bounds = host.getContentAreaBounds()
            return belowY - hostTop + height > bounds.bottom &&
                aboveBottom - hostTop - (height + 8.dp) >= bounds.top
        }
    }

    sealed interface BackgroundStyle {
        object Transparent : BackgroundStyle

        /** Dims the window but [cutoutPath]; [lifted] draws over the dim, lifted with what the path leaves out */
        class Cutout(val cutoutPath: Path, val lifted: Drawable? = null) : BackgroundStyle {

            companion object {

                fun fromView(view: View, roundRadius: Float = 0f, offset: Int = 0): Cutout = Cutout(
                    view.frameAsPath(
                        roundRadius = roundRadius,
                        offset = offset.toFloat()
                    )
                )

                fun fromView(
                    view: View,
                    roundRadius: Float = 0f,
                    horizontalOffset: Int = 0,
                    verticalOffset: Int = 0
                ): Cutout = Cutout(
                    view.frameAsPath(
                        roundRadius = roundRadius,
                        horizontalOffset = horizontalOffset.toFloat(),
                        verticalOffset = verticalOffset.toFloat()
                    )
                )
            }
        }
    }

    sealed interface BackdropStyle {
        object BlurDimmed : BackdropStyle

        // Keeps colorful backgrounds unsaturated without adding a dim overlay
        object PlainBlur : BackdropStyle

        object Dimmed : BackdropStyle
        object Transparent : BackdropStyle
    }
}
