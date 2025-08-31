package org.mytonwallet.app_air.uicreatewallet.viewControllers.wordDisplay

import android.annotation.SuppressLint
import android.content.Context
import org.mytonwallet.app_air.uicreatewallet.viewControllers.wordCheck.WordCheckVC
import org.mytonwallet.app_air.uisettings.viewControllers.RecoveryPhraseVC
import kotlin.random.Random

@SuppressLint("ViewConstructor")
class WordDisplayVC(
    context: Context,
    private val words: Array<String>,
    private val isFirstWallet: Boolean,
    // Used when adding new account (not first account!)
    private val passedPasscode: String?
) :
    RecoveryPhraseVC(context, words) {

    override val shouldDisplayTopBar = false

    override fun donePressed() {
        gotoWordCheck()
    }

    private fun gotoWordCheck() {
        // Get 3 random indices
        val numbers = (1..words.size).toList()
        val shuffledNumbers = numbers.shuffled(Random)
        val randomNumbers = shuffledNumbers.take(3)

        push(
            WordCheckVC(
                context,
                words,
                randomNumbers.sorted(),
                isFirstWallet,
                passedPasscode
            )
        )
    }
}
