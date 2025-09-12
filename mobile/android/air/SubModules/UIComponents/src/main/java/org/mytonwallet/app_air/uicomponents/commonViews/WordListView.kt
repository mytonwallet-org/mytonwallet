package org.mytonwallet.app_air.uicomponents.commonViews

import android.annotation.SuppressLint
import android.content.Context
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import org.mytonwallet.app_air.uicomponents.widgets.WView
import kotlin.math.ceil

@SuppressLint("ViewConstructor")
class WordListView(context: Context) : WView(context) {

    fun setupViews(words: List<String>) {
        val rowsCount = ceil(words.size / 2.0).toInt()

        // To increase performance, decided to use a single view for each row, totally 4 text views!
        var leftIndexes = ""
        var leftWords = ""
        var rightIndexes = ""
        var rightWords = ""
        words.forEachIndexed { index, word ->
            if (index < rowsCount) {
                leftIndexes += "\n${index + 1}."
                leftWords += "\n$word"
            } else {
                rightIndexes += "\n${index + 1}."
                rightWords += "\n$word"
            }
        }
        val leftWordItemView = WordListItemView(context)
        leftWordItemView.setupViews(leftIndexes.substring(1), leftWords.substring(1))
        val rightWordItemView = WordListItemView(context)
        rightWordItemView.setupViews(rightIndexes.substring(1), rightWords.substring(1))

        addView(leftWordItemView, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        addView(rightWordItemView, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))

        setConstraints {
            toTop(leftWordItemView)
            toStart(leftWordItemView)
            startToEnd(rightWordItemView, leftWordItemView, 48f)
            toTop(rightWordItemView)
            toEnd(rightWordItemView)
        }
    }
}
