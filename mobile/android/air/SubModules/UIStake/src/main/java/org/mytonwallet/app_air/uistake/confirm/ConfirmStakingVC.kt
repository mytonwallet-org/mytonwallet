package org.mytonwallet.app_air.uistake.confirm

import android.annotation.SuppressLint
import android.content.Context
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import androidx.constraintlayout.widget.ConstraintLayout
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uistake.confirm.view.StakingPasscodeView
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.api.verifyPassword
import org.mytonwallet.app_air.walletcore.models.MToken
import java.math.BigInteger

@SuppressLint("ViewConstructor")
class ConfirmStakingVC(
    context: Context,
    private val topTitle: String,
    val task: (passcode: String) -> Unit,
    val data: Pair<MToken, BigInteger>,
    val showPositiveSignForAmount: Boolean,
    val messageString: String,
) : WViewController(context) {

    private var isDoingTask = false

    override val isSwipeBackAllowed: Boolean
        get() = !isDoingTask

    private val passcodeView: StakingPasscodeView by lazy {
        val v = StakingPasscodeView(
            window!!,
            light = ThemeManager.isDark,
            animated = false,
            token = data.first,
            amountInCrypto = data.second,
            showPositiveSignForAmount = showPositiveSignForAmount,
            messageString = messageString
        ) { passcode, checkIsCorrectCallback ->
            enteredPasscode(passcode, checkIsCorrectCallback)
        }
        v
    }

    override fun setupViews() {
        super.setupViews()

        setNavTitle(topTitle)
        setupNavBar(true)
        navigationBar?.addCloseButton()

        view.addView(passcodeView, ConstraintLayout.LayoutParams(MATCH_PARENT, 0))

        view.setConstraints({
            topToBottom(passcodeView, navigationBar!!)
            toCenterX(this@ConfirmStakingVC.passcodeView)
            toBottomPx(passcodeView, navigationController?.getSystemBars()?.bottom ?: 0)
        })

        updateTheme()
    }

    override fun updateTheme() {
        super.updateTheme()
        view.setBackgroundColor(WColor.Background.color)
    }

    override fun onBackPressed(): Boolean {
        if (isDoingTask)
            return false
        return super.onBackPressed()
    }

    private fun enteredPasscode(passcode: String, checkIsCorrectCallback: (Boolean) -> Unit) {
        WalletCore.verifyPassword(passcode) { isSuccess, _ ->
            checkIsCorrectCallback(isSuccess ?: false)
            if (isSuccess == true) {
                view.lockView()
                isDoingTask = true
                task(passcode)
                navigationBar?.fadeOutActions()
                passcodeView.showIndicator()
            }
        }
    }

}
