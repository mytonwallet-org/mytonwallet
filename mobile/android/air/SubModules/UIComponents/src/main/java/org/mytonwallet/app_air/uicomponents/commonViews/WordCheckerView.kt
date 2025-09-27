package org.mytonwallet.app_air.uicomponents.commonViews

import android.annotation.SuppressLint
import android.content.Context
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.constraintlayout.helper.widget.Flow
import androidx.core.view.children
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uicomponents.widgets.fadeOut
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcore.constants.PossibleWords
import kotlin.random.Random

@SuppressLint("ViewConstructor")
class WordCheckerView(
    context: Context,
    val onSelect: () -> Unit
) : WView(context), WThemedView {

    private val indexLabel = WLabel(context).apply {
        setStyle(17f)
        setTextColor(WColor.SecondaryText)
        gravity = Gravity.END or Gravity.CENTER_VERTICAL
    }

    private val suggestionsContainerView = WView(context)
    private val flowHelper = Flow(context).apply {
        id = generateViewId()
        setWrapMode(Flow.WRAP_CHAIN)
        setHorizontalStyle(Flow.CHAIN_PACKED)
        setHorizontalAlign(Flow.HORIZONTAL_ALIGN_START)
        setHorizontalBias(0f)
        setHorizontalGap(8.dp)
        setVerticalGap(8.dp)
    }
    private val wordViews = mutableListOf<WView>()

    override fun setupViews() {
        super.setupViews()

        addView(indexLabel, LayoutParams(28.dp, 52.dp))
        addView(suggestionsContainerView, LayoutParams(0, WRAP_CONTENT))
        suggestionsContainerView.addView(flowHelper, LayoutParams(MATCH_PARENT, WRAP_CONTENT))

        setConstraints {
            toTop(indexLabel)
            toStart(indexLabel)
            setHorizontalBias(suggestionsContainerView.id, 0f)
            toCenterY(suggestionsContainerView)
            toStart(suggestionsContainerView, 44f)
            toEnd(suggestionsContainerView)
        }

        suggestionsContainerView.setConstraints {
            allEdges(flowHelper)
        }
    }

    private var selectedIndex: Int? = null
    private var wordOptions: List<String>? = null
    private var correctWord: String? = null

    @SuppressLint("SetTextI18n")
    private fun configureViews(index: Int, word: String) {
        selectedIndex = null
        unlockView()
        correctWord = word
        wordOptions = (getRandomAroundWord(word) + word).shuffled()
        indexLabel.setStyle(17f)
        indexLabel.text = "$index."
        indexLabel.setTextColor(WColor.SecondaryText)
        setupWordViews(wordOptions!!)
    }

    fun config(index: Int, word: String, animated: Boolean) {
        if (animated) {
            fadeOut(duration = AnimationConstants.VERY_QUICK_ANIMATION) {
                configureViews(index, word)
                fadeIn(duration = AnimationConstants.VERY_QUICK_ANIMATION)
            }
        } else {
            configureViews(index, word)
        }
    }

    private fun setupWordViews(words: List<String>) {
        wordViews.forEach { suggestionsContainerView.removeView(it) }
        wordViews.clear()

        val viewIds = IntArray(words.size)

        words.forEachIndexed { wordIndex, wordText ->
            val wordButton = WLabel(context).apply {
                id = generateViewId()
                text = wordText
                setTextColor(WColor.PrimaryText)
                setStyle(16f)
                setPaddingDp(14)
                setTextColor(WColor.PrimaryText.color)
            }

            val wordButtonContainer = WView(context).apply {
                addView(wordButton)
                setConstraints {
                    allEdges(wordButton)
                }
                animateBackgroundColor(
                    WColor.Background.color,
                    16f.dp,
                    WColor.Background.color,
                    2.dp,
                    duration = 0
                )
                addRippleEffect(WColor.BackgroundRipple.color, 16f.dp)
                setOnClickListener {
                    if (selectedIndex == wordIndex)
                        return@setOnClickListener
                    isValidatedAndWrong = false
                    selectedIndex?.let {
                        animateWordColor(it, WColor.PrimaryText.color, false)
                    }
                    selectedIndex = wordIndex
                    animateToColor(wordIndex, WColor.Tint.color)
                    onSelect()
                }
            }
            wordViews.add(wordButtonContainer)
            suggestionsContainerView.addView(
                wordButtonContainer,
                LayoutParams(WRAP_CONTENT, WRAP_CONTENT)
            )
            viewIds[wordIndex] = wordButtonContainer.id
        }

        flowHelper.referencedIds = viewIds
    }

    private val allWords = PossibleWords.All.toList()
    private fun getRandomAroundWord(target: String): List<String> {
        val index = allWords.indexOf(target)
        if (index == -1) return emptyList()

        val n = Random.nextInt(0, 4)

        val before = allWords.subList((index - n).coerceAtLeast(0), index)
        val after = allWords.subList(index + 1, (index + 1 + (3 - n)).coerceAtMost(allWords.size))

        return before + after
    }

    override fun updateTheme() {
        wordViews.forEach {
            it.setBackgroundColor(WColor.Background.color, 16f.dp)
            it.addRippleEffect(WColor.BackgroundRipple.color, 16f.dp)
        }
    }

    private fun animateToColor(index: Int, color: Int) {
        indexLabel.setStyle(17f, WFont.SemiBold)
        indexLabel.animateTextColor(
            color,
            AnimationConstants.VERY_QUICK_ANIMATION
        )
        animateWordColor(index, color, true)
    }

    private fun animateWordColor(index: Int, color: Int, showBorder: Boolean) {
        wordViews[index].apply {
            animateBackgroundColor(
                WColor.Background.color,
                16f.dp,
                if (showBorder) color else WColor.Background.color,
                2.dp
            )
            (children.firstOrNull() as? WLabel)?.apply {
                animateTextColor(
                    color,
                    AnimationConstants.VERY_QUICK_ANIMATION
                )
            }
        }
    }

    var isValidatedAndWrong = false

    val isWordSelected: Boolean
        get() {
            return selectedIndex != null
        }

    fun validate(): Boolean {
        val isCorrect = wordOptions?.getOrNull(selectedIndex ?: -1) == correctWord
        animateToColor(selectedIndex!!, if (isCorrect) WColor.Green.color else WColor.Red.color)
        if (isCorrect)
            lockView()
        else
            isValidatedAndWrong = true
        return isCorrect
    }
}
