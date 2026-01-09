package org.mytonwallet.app_air.uicomponents.widgets.menu

import android.view.View
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.FrameLayout
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.getLocationOnScreen
import org.mytonwallet.app_air.uicomponents.extensions.unspecified
import org.mytonwallet.app_air.uicomponents.widgets.INavigationPopup
import org.mytonwallet.app_air.uicomponents.widgets.lockView
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup.Item.Config.Icon
import org.mytonwallet.app_air.uicomponents.widgets.unlockView
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.x
import org.mytonwallet.app_air.walletbasecontext.utils.y

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
                val textMargin: Int? = null
            ) : Config()

            data class SelectableItem(
                val title: CharSequence,
                val subtitle: CharSequence?,
                val isSelected: Boolean
            ) : Config()

            data class CustomView(
                val customView: FrameLayout
            ) : Config()

            data class Icon(
                val icon: Int,
                val tintColor: WColor? = null,
                val iconSize: Int? = null,
                val iconMargin: Int? = null,
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

                else -> {
                    null
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

        fun getIconMargin(): Int? {
            return when (config) {
                is Config.Item -> {
                    config.icon?.iconMargin
                }

                else -> {
                    null
                }
            }
        }

        fun getTextMargin(): Int? {
            return when (config) {
                is Config.Item -> {
                    config.textMargin
                }

                else -> {
                    null
                }
            }
        }

        fun getTitle(): CharSequence? {
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

                else -> {
                    null
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

                else -> {
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

                else -> {
                    false
                }
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
            aboveView: Boolean,
            centerHorizontally: Boolean = false,
            onWillDismiss: (() -> Unit)? = null,
        ): INavigationPopup {
            view.lockView()

            lateinit var popupWindow: WNavigationPopup

            val initialPopupView = WMenuPopupView(
                view.context, items,
                onWillDismiss = onWillDismiss,
                onDismiss = {
                    popupWindow.dismiss()
                })

            popupWindow = WNavigationPopup(initialPopupView, popupWidth).apply {
                setOnDismissListener {
                    view.post {
                        view.unlockView()
                    }
                }
            }

            val location = view.getLocationOnScreen()
            val offset = xOffset + if (centerHorizontally) {
                val popupMeasuredWidth = if (popupWidth == WRAP_CONTENT) {
                    initialPopupView.measure(0.unspecified, 0.unspecified)
                    initialPopupView.measuredWidth
                } else {
                    popupWidth
                }
                (view.width - popupMeasuredWidth) / 2
            } else {
                0
            }

            popupWindow.showAtLocation(
                x = location.x + offset,
                y = location.y + yOffset + if (aboveView) 0 else (view.height + 8.dp)
            )
            return popupWindow
        }
    }
}
