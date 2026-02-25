package org.mytonwallet.app_air.uisettings.viewControllers.language

import android.content.Context
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import androidx.recyclerview.widget.RecyclerView
import org.mytonwallet.app_air.uicomponents.base.WRecyclerViewAdapter
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.commonViews.cells.HeaderCell
import org.mytonwallet.app_air.uicomponents.commonViews.cells.TitleSubtitleSelectionCell
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.LastItemPaddingDecoration
import org.mytonwallet.app_air.uicomponents.helpers.LinearLayoutManagerAccurateOffset
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WRecyclerView
import org.mytonwallet.app_air.uiwidgets.configurations.WidgetsConfigurations
import org.mytonwallet.app_air.walletbasecontext.WBaseStorage
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.localization.WLanguage
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.WalletContextManager
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.utils.IndexPath
import org.mytonwallet.app_air.walletcore.pushNotifications.AirPushNotifications
import java.lang.ref.WeakReference

class LanguageVC(context: Context) : WViewController(context),
    WRecyclerViewAdapter.WRecyclerViewDataSource {
    override val TAG = "Language"

    companion object {
        val languages = arrayOf(
            WLanguage.ENGLISH,
            WLanguage.SPANISH,
            WLanguage.RUSSIAN,
            WLanguage.CHINESE_SIMPLIFIED,
            WLanguage.CHINESE_TRADITIONAL,
            WLanguage.TURKISH,
            WLanguage.GERMAN,
            WLanguage.THAI,
            WLanguage.UKRAINIAN,
            WLanguage.POLISH,
            //WLanguage.PERSIAN,
        )

        val HEADER_CELL = WCell.Type(1)
        val LANGUAGE_CELL = WCell.Type(2)
    }

    override val shouldDisplayBottomBar = true

    private val rvAdapter =
        WRecyclerViewAdapter(WeakReference(this), arrayOf(HEADER_CELL, LANGUAGE_CELL))

    private val recyclerView: WRecyclerView by lazy {
        val rv = WRecyclerView(this)
        rv.adapter = rvAdapter
        val layoutManager = LinearLayoutManagerAccurateOffset(context)
        layoutManager.isSmoothScrollbarEnabled = true
        rv.setLayoutManager(layoutManager)
        rv.addItemDecoration(
            LastItemPaddingDecoration(
                navigationController?.getSystemBars()?.bottom ?: 0
            )
        )
        rv.setItemAnimator(null)
        rv.addOnScrollListener(object : RecyclerView.OnScrollListener() {
            override fun onScrolled(recyclerView: RecyclerView, dx: Int, dy: Int) {
                super.onScrolled(recyclerView, dx, dy)
                if (dx == 0 && dy == 0)
                    return
                updateBlurViews(recyclerView)
            }
        })
        rv.setPadding(
            ViewConstants.HORIZONTAL_PADDINGS.dp,
            0,
            ViewConstants.HORIZONTAL_PADDINGS.dp,
            0
        )
        rv
    }

    override fun setupViews() {
        super.setupViews()

        setNavTitle(LocaleController.getString("Language"))
        setupNavBar(true)

        view.addView(recyclerView, ViewGroup.LayoutParams(MATCH_PARENT, 0))
        view.setConstraints {
            topToBottom(recyclerView, navigationBar!!)
            toCenterX(recyclerView)
            toBottom(recyclerView)
        }

        updateTheme()
    }

    override fun updateTheme() {
        super.updateTheme()
        view.setBackgroundColor(WColor.SecondaryBackground.color)
    }

    override fun recyclerViewNumberOfSections(rv: RecyclerView): Int {
        return 2
    }

    override fun recyclerViewNumberOfItems(rv: RecyclerView, section: Int): Int {
        return when (section) {
            0 -> 1
            else -> languages.size
        }
    }

    override fun recyclerViewCellType(rv: RecyclerView, indexPath: IndexPath): WCell.Type {
        return when (indexPath.section) {
            0 -> HEADER_CELL
            else -> LANGUAGE_CELL
        }
    }

    override fun recyclerViewCellView(rv: RecyclerView, cellType: WCell.Type): WCell {
        return when (cellType) {
            HEADER_CELL -> {
                HeaderCell(
                    context,
                    20f
                )
            }

            else -> {
                TitleSubtitleSelectionCell(context)
            }
        }
    }

    override fun recyclerViewConfigureCell(
        rv: RecyclerView,
        cellHolder: WCell.Holder,
        indexPath: IndexPath
    ) {
        when (indexPath.section) {
            0 -> {
                (cellHolder.cell as HeaderCell).configure(
                    title = LocaleController.getString("Language"),
                    titleColor = WColor.Tint
                )
            }

            else -> {
                val language = languages[indexPath.row]
                (cellHolder.cell as TitleSubtitleSelectionCell).configure(
                    title = language.englishName,
                    subtitle = language.nativeName,
                    isSelected = WGlobalStorage.getLangCode() == language.langCode,
                    isFirst = false,
                    isLast = indexPath.row == languages.size - 1
                ) {
                    WGlobalStorage.setLangCode(language.langCode)
                    AirPushNotifications.refreshSubscriptions()
                    switchLanguageIfRequired(language)
                    if (LocaleController.init(context, WGlobalStorage.getLangCode())) {
                        WalletContextManager.delegate?.restartApp()
                        WBaseStorage.setActiveLanguage(language.langCode)
                        WidgetsConfigurations.reloadWidgets(context)
                    }
                }
            }
        }
    }

    private fun switchLanguageIfRequired(nextLanguage: WLanguage) {
        /*if (nextLanguage == WLanguage.PERSIAN) {
            FontManager.setActiveFont(context, FontFamily.VAZIR)
        } else if (FontManager.activeFont == FontFamily.VAZIR) {
            FontManager.setActiveFont(context, FontFamily.MISANS)
        }*/
    }

}
