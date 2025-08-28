package org.mytonwallet.app_air.uisettings.viewControllers

import android.annotation.SuppressLint
import android.content.Context
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.constraintlayout.widget.ConstraintLayout
import org.mytonwallet.app_air.uicomponents.R
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.commonViews.HeaderAndActionsView
import org.mytonwallet.app_air.uicomponents.commonViews.WordListView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.WButton
import org.mytonwallet.app_air.uicomponents.widgets.WScrollView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.walletcontext.helpers.LocaleController
import org.mytonwallet.app_air.walletcontext.theme.WColor
import org.mytonwallet.app_air.walletcontext.theme.color
import org.mytonwallet.app_air.walletcontext.utils.toProcessedSpannableStringBuilder
import java.lang.ref.WeakReference

@SuppressLint("ViewConstructor")
open class RecoveryPhraseVC(context: Context, words: Array<String>) : WViewController(context) {

    override val protectFromScreenRecord = true
    override val shouldDisplayBottomBar = true
    override val ignoreSideGuttering = true

    private val wordsCount = words.size

    private val headerView: HeaderAndActionsView by lazy {
        val title = LocaleController.getFormattedString(
            "%1\$d Secret Words",
            listOf(wordsCount.toString())
        )
        val subtitle = LocaleController.getString("\$mnemonic_list_description") +
            "\n" +
            LocaleController.getString("\$mnemonic_warning")
        val v = HeaderAndActionsView(
            context,
            R.raw.animation_note,
            null,
            false,
            title,
            subtitle.toProcessedSpannableStringBuilder(),
            onStarted = {
                scrollView.fadeIn()
            }
        )
        v
    }

    private val wordsView: WordListView by lazy {
        val wordsView = WordListView(context)
        wordsView.setupViews(words.toList())
        wordsView
    }

    private val doneButton: WButton by lazy {
        val btn = WButton(context, WButton.Type.PRIMARY)
        btn.text =
            LocaleController.getString("Done")
        btn.setOnClickListener {
            donePressed()
        }
        btn
    }

    private val scrollingContentView: WView by lazy {
        val v = WView(context)
        v.layoutDirection = View.LAYOUT_DIRECTION_LTR
        v.addView(headerView, ConstraintLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        v.addView(wordsView, ConstraintLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        v.addView(doneButton, ConstraintLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        v.setConstraints {
            toTopPx(
                headerView,
                WNavigationBar.DEFAULT_HEIGHT.dp + (navigationController?.getSystemBars()?.top
                    ?: 0)
            )
            toCenterX(headerView)
            topToBottom(wordsView, headerView, 16F)
            toCenterX(wordsView, 45F)
            topToBottom(doneButton, wordsView, 16F)
            toCenterX(doneButton, 48F)
            toBottomPx(
                doneButton,
                48.dp + (navigationController?.getSystemBars()?.bottom ?: 0)
            )
        }
        v
    }

    private val scrollView: WScrollView by lazy {
        val sv = WScrollView(WeakReference(this))
        sv.addView(scrollingContentView, ConstraintLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        sv
    }

    override fun setupViews() {
        super.setupViews()

        setNavTitle("")
        setupNavBar(true)

        scrollView.alpha = 0f
        view.addView(scrollView, ConstraintLayout.LayoutParams(0, 0))
        view.setConstraints({
            allEdges(scrollView)
        })

        val scrollOffsetToShowNav = (WNavigationBar.DEFAULT_HEIGHT + 135).dp
        scrollView.onScrollChange = { y ->
            if (y > 0) {
                topReversedCornerView?.resumeBlurring()
            } else {
                topReversedCornerView?.pauseBlurring(false)
            }
            if (y > scrollOffsetToShowNav) {
                setNavTitle(
                    LocaleController.getFormattedString(
                        "%1\$d Secret Words",
                        listOf(wordsCount.toString())
                    )
                )
                setTopBlur(visible = true, animated = true)
            } else {
                setNavTitle("")
                setTopBlur(visible = false, animated = true)
            }
        }

        updateTheme()
    }

    override fun updateTheme() {
        super.updateTheme()
        view.setBackgroundColor(WColor.Background.color)
    }

    open fun donePressed() {
        navigationController?.pop()
    }

}
