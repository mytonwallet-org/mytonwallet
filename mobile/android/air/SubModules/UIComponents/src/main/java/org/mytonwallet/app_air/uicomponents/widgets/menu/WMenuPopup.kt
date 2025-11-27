package org.mytonwallet.app_air.uicomponents.widgets.menu

import android.annotation.SuppressLint
import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import android.view.Gravity
import android.view.View
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.PopupHelpers
import org.mytonwallet.app_air.uicomponents.widgets.lockView
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup.Item.Config.Icon
import org.mytonwallet.app_air.uicomponents.widgets.unlockView
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

class WMenuPopup {

    data class Item(
        val config: Config,
        var hasSeparator: Boolean = false,
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
            ) : Config()

            data class SelectableItem(
                val title: CharSequence,
                val subtitle: CharSequence?,
                val isSelected: Boolean
            ) : Config()

            data class Icon(
                val icon: Int,
                val tintColor: WColor? = null,
                val iconSize: Int? = null
            )
        }

        fun getIcon(): Int? {
            return when (config) {
                is Config.Back -> {
                    org.mytonwallet.app_air.icons.R.drawable.ic_menu_back
                }

                is Config.Item -> {
                    config.icon?.icon
                }

                is Config.SelectableItem -> {
                    if (config.isSelected) org.mytonwallet.app_air.uicomponents.R.drawable.ic_radio_fill else null
                }
            }
        }

        fun getIconTint(): Int? {
            return when (config) {
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
        }

        fun getIconSize(): Int? {
            return when (config) {
                is Config.Item -> {
                    config.icon?.iconSize
                }

                else -> {
                    null
                }
            }
        }

        fun getTitle(): CharSequence {
            return when (config) {
                is Config.Back -> {
                    LocaleController.getString("Back")
                }

                is Config.Item -> {
                    config.title
                }

                is Config.SelectableItem -> {
                    config.title
                }
            }
        }

        fun getTitleColor(): Int? {
            return when (config) {
                is Config.Item -> {
                    config.titleColor
                }

                else ->
                    null
            }
        }

        fun getSubTitle(): CharSequence? {
            return when (config) {
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
        }

        fun getSubItems(): List<Item>? {
            return when (config) {
                is Config.Back -> {
                    null
                }

                is Config.Item -> {
                    config.subItems
                }

                is Config.SelectableItem -> {
                    null
                }
            }
        }

        fun getIsSubItem(): Boolean {
            return when (config) {
                is Config.Back -> {
                    false
                }

                is Config.Item -> {
                    config.isSubItem
                }

                is Config.SelectableItem -> {
                    false
                }
            }
        }
    }

    companion object {
        @SuppressLint("ClickableViewAccessibility")
        fun present(
            view: View,
            items: List<Item>,
            popupWidth: Int = WRAP_CONTENT,
            offset: Int = 0,
            verticalOffset: Int = 0,
            aboveView: Boolean,
            centerHorizontally: Boolean = false,
            onWillDismiss: (() -> Unit)? = null,
        ): WPopupWindow {
            view.lockView()

            lateinit var popupWindow: WPopupWindow

            val popupView = WMenuPopupView(
                view.context, items,
                onWillDismiss = onWillDismiss,
                onDismiss = {
                    popupWindow.dismiss()
                })

            popupWindow = WPopupWindow(popupView, popupWidth).apply {
                isOutsideTouchable = true
                setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))

                setOnDismissListener {
                    view.post {
                        view.unlockView()
                    }
                }
            }
            popupView.popupWindow = popupWindow

            val location = IntArray(2)
            view.getLocationOnScreen(location)

            val offset = offset + if (centerHorizontally) {
                val popupMeasuredWidth = if (popupWidth == WRAP_CONTENT) {
                    popupView.measure(
                        View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED),
                        View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED)
                    )
                    popupView.measuredWidth
                } else {
                    popupWidth
                }
                (view.width - popupMeasuredWidth) / 2
            } else {
                0
            }

            popupWindow.showAtLocation(
                view,
                Gravity.NO_GRAVITY,
                location[0] + offset - 4.dp,
                location[1] + verticalOffset - 8.dp + if (aboveView) 0 else (view.height + 4.dp)
            )

            popupView.present(initialHeight = 0)

            PopupHelpers.popupShown(popupWindow)

            return popupWindow
        }
    }
}
