package org.mytonwallet.app_air.uicomponents.widgets.menu

import android.graphics.Path
import android.graphics.drawable.Drawable
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
                val submenuTransition: SubmenuTransition = SubmenuTransition.PAGE
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
                val drawable: Drawable? = null
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

        fun getIconTint(): Int? = when (config) {
            is Config.Item -> {
                config.icon?.tintColor?.color
            }

            is Config.SelectableItem -> {
                WColor.Tint.color
            }

            Config.Back -> {
                WColor.PrimaryLightText.color
            }

            else -> {
                WColor.SecondaryText.color
            }
        }

        fun getIconDrawable(): Drawable? = when (config) {
            is Config.Item -> config.icon?.drawable
            else -> null
        }

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
            placement: ((width: Int, height: Int) -> Vec2i)? = null
        ): INavigationPopup {
            if (cancelsAncestorTouches) view.cancelAncestorTouches()
            view.lockView()

            lateinit var popupWindow: WNavigationPopup

            val initialPopupView = WMenuPopupView(
                view.context,
                items,
                onWillDismiss = onWillDismiss,
                onDismiss = {
                    popupWindow.dismiss()
                }
            )

            popupWindow =
                WNavigationPopup(
                    initialPopupView,
                    popupWidth,
                    windowBackgroundStyle,
                    backdropStyle,
                    usePillShadow
                ).apply {
                    setOnDismissListener {
                        view.post {
                            view.unlockView()
                        }
                        onDidDismiss?.invoke()
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

        class Cutout(val cutoutPath: Path) : BackgroundStyle {

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

        object Dimmed : BackdropStyle
        object Transparent : BackdropStyle
    }
}
