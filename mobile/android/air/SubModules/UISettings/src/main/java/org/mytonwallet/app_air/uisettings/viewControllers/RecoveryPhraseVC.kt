package org.mytonwallet.app_air.uisettings.viewControllers

import android.annotation.SuppressLint
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.Toast
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.core.view.isGone
import org.mytonwallet.app_air.uicomponents.R
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.base.showAlert
import org.mytonwallet.app_air.uicomponents.commonViews.WordListView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.helpers.HapticType
import org.mytonwallet.app_air.uicomponents.helpers.Haptics
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.spans.WTypefaceSpan
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.widgets.WAnimationView
import org.mytonwallet.app_air.uicomponents.widgets.WButton
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WScrollView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.DEBUG_MODE
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.toProcessedSpannableStringBuilder
import org.mytonwallet.app_air.walletcontext.WalletContextManager
import org.mytonwallet.app_air.walletcontext.helpers.WordCheckMode
import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha
import org.mytonwallet.app_air.walletcore.helpers.PrivateKeyHelper
import java.lang.ref.WeakReference
import kotlin.random.Random

@SuppressLint("ViewConstructor")
open class RecoveryPhraseVC(
    context: Context,
    private val network: MBlockchainNetwork,
    private val words: Array<String>
) :
    WViewController(context) {
    override val TAG = "RecoveryPhrase"

    override val protectFromScreenRecord = true
    override val shouldDisplayBottomBar = true
    override val ignoreSideGuttering = true

    private val wordsCount = words.size

    open val skipTitle = LocaleController.getString("Close")
    open val checkMode: WordCheckMode = WordCheckMode.Check

    private var skipAvailable = checkMode == WordCheckMode.Check || DEBUG_MODE
    private var isShowingPrivateKey = wordsCount == 1 && PrivateKeyHelper.isValidPrivateKeyHex(words.first())

    val animationView = WAnimationView(context).apply {
        play(
            R.raw.animation_bill, true,
            onStart = {
                scrollView.fadeIn()
            })
    }

    private val subtitleLabel = WLabel(context).apply {
        setStyle(17f, WFont.Regular)
        setLineHeight(TypedValue.COMPLEX_UNIT_SP, 26f)
        text =
            LocaleController.getString(if (isShowingPrivateKey) "\$private_key_description" else "\$mnemonic_list_description")
                .toProcessedSpannableStringBuilder()
        gravity = Gravity.CENTER
        setTextColor(WColor.PrimaryText)
    }

    private val warningLabel = WLabel(context).apply {
        setStyle(17f, WFont.Medium)
        setLineHeight(TypedValue.COMPLEX_UNIT_SP, 26f)
        text =
            LocaleController.getString("\$mnemonic_warning").trim()
                .toProcessedSpannableStringBuilder()
        gravity = Gravity.CENTER
        setPaddingDp(16, 12, 16, 12)
        setTextColor(WColor.Red)
    }

    private fun warningText(key: String?): SpannableStringBuilder {
        return SpannableStringBuilder().apply {
            key?.let {
                append(
                    LocaleController.getString(key)
                        .toProcessedSpannableStringBuilder()
                )
                append("\n\n")
            }
            val redWarningStart = length
            append(LocaleController.getString("Other apps will be able to read your recovery phrase!"))
            setSpan(
                WTypefaceSpan(WFont.SemiBold.typeface, WColor.Red.color),
                redWarningStart,
                length,
                Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
            )
        }
    }

    private val copyToClipboardButton = WLabel(context).apply {
        setStyle(17f, WFont.SemiBold)
        setLineHeight(TypedValue.COMPLEX_UNIT_SP, 26f)
        text =
            LocaleController.getString("Copy to Clipboard")
        gravity = Gravity.CENTER
        setPadding(16.dp, 0, 16.dp, 0)
        setTextColor(WColor.Tint)
        isTinted = true
        setOnClickListener {
            showAlert(
                title = LocaleController.getString("Security Warning"),
                text = warningText(if (isShowingPrivateKey) null else "\$copy_mnemonic_warning"),
                button = LocaleController.getString("Copy Anyway"),
                buttonPressed = {
                    val clipboard =
                        context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                    val clip = ClipData.newPlainText("Wallet Address", words.joinToString(" "))
                    clipboard.setPrimaryClip(clip)
                    Haptics.play(context, HapticType.LIGHT_TAP)
                    Toast.makeText(
                        context,
                        LocaleController.getString("Secret phrase was copied to clipboard"),
                        Toast.LENGTH_SHORT
                    ).show()
                },
                primaryIsDanger = true,
                secondaryButton = LocaleController.getString(if (isShowingPrivateKey) "Cancel" else "See Words")
            )
        }
    }

    private val wordsView: WordListView by lazy {
        val wordsView = WordListView(context)
        wordsView.setupViews(words.toList())
        wordsView
    }

    val letsCheckButton: WButton by lazy {
        val btn = WButton(context, WButton.Type.PRIMARY)
        btn.text =
            LocaleController.getString("Let's Check!")
        btn.setOnClickListener {
            gotoWordCheck()
        }
        btn.isGone = isShowingPrivateKey
        btn
    }

    val skipButton: WButton by lazy {
        val btn = WButton(context, if (isShowingPrivateKey) WButton.Type.PRIMARY else WButton.Type.SECONDARY)
        btn.text = skipTitle
        btn.setOnClickListener {
            skipPressed()
        }
        btn.isGone = !skipAvailable
        btn
    }

    private val scrollingContentView: WView by lazy {
        val v = WView(context)
        v.layoutDirection = View.LAYOUT_DIRECTION_LTR
        v.addView(animationView, ConstraintLayout.LayoutParams(132.dp, 132.dp))
        v.addView(subtitleLabel, ConstraintLayout.LayoutParams(0, WRAP_CONTENT))
        v.addView(warningLabel, ConstraintLayout.LayoutParams(0, WRAP_CONTENT))
        v.addView(copyToClipboardButton, ConstraintLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        v.addView(wordsView, ConstraintLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        v.addView(letsCheckButton, ConstraintLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        v.addView(skipButton, ConstraintLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        v.setConstraints {
            toTopPx(
                animationView,
                WNavigationBar.DEFAULT_HEIGHT.dp +
                    (navigationController?.getSystemBars()?.top ?: 0)
            )
            toCenterX(animationView)
            topToBottom(subtitleLabel, animationView, 37f)
            toCenterX(subtitleLabel, 44f)
            topToBottom(warningLabel, subtitleLabel, 23f)
            toCenterX(warningLabel, 24f)
            topToBottom(copyToClipboardButton, warningLabel, 34f)
            toCenterX(copyToClipboardButton, 48f)
            topToBottom(wordsView, copyToClipboardButton, 46f)
            toCenterX(wordsView, 45f)
            topToBottom(letsCheckButton, wordsView, 40f)
            toCenterX(letsCheckButton, 48f)
            if (skipAvailable) {
                topToBottom(skipButton, letsCheckButton, if (isShowingPrivateKey) 40f else 16f)
                toCenterX(skipButton, 48f)
                toBottomPx(
                    skipButton,
                    16.dp + (navigationController?.getSystemBars()?.bottom ?: 0)
                )
            } else {
                toBottomPx(
                    letsCheckButton,
                    16.dp + (navigationController?.getSystemBars()?.bottom ?: 0)
                )
            }
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

        setNavTitle(
            LocaleController.getPluralOrFormat(
                if (isShowingPrivateKey) "Private Key" else "%1\$d Secret Words",
                wordsCount,
            ) + network.localizedIdentifier
        )
        setupNavBar(true)
        setTopBlur(visible = false, animated = false)

        scrollView.alpha = 0f
        view.addView(scrollView, ConstraintLayout.LayoutParams(0, 0))
        view.setConstraints {
            allEdges(scrollView)
        }

        scrollView.onScrollChange = { y ->
            if (y > 0) {
                topReversedCornerView?.resumeBlurring()
            } else {
                topReversedCornerView?.pauseBlurring(false)
            }
            setTopBlur(visible = y > 0, animated = true)
        }

        updateTheme()
    }

    override fun updateTheme() {
        super.updateTheme()
        view.setBackgroundColor(WColor.Background.color)
        warningLabel.setBackgroundColor(WColor.Red.color.colorWithAlpha(20), 16f.dp)
    }

    private fun gotoWordCheck() {
        val numbers = (1..words.size).toList()
        val shuffledNumbers = numbers.shuffled(Random)
        val randomNumbers = shuffledNumbers.take(3)

        push(
            WalletContextManager.delegate?.getWordCheckVC(
                network,
                words,
                randomNumbers.sorted(),
                checkMode
            ) as WViewController
        )
    }

    open fun skipPressed() {
        pop()
    }

    override fun presentScreenRecordProtectionView() {
        view.post {
            showAlert(
                title = LocaleController.getString("Security Warning"),
                text = warningText("\$screenshot_mnemonic_warning"),
                button = LocaleController.getString("See Words"),
            )
        }
    }

}
