package org.mytonwallet.app_air.walletcontext.helpers

import android.content.Context
import android.os.Build
import android.os.Handler
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.fragment.app.FragmentActivity
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.logger.Logger
import java.util.concurrent.Executor

class BiometricHelpers {
    companion object {
        fun canAuthenticate(context: Context): Boolean {
            val biometricManager = BiometricManager.from(context)
            return biometricManager.canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_STRONG) == BiometricManager.BIOMETRIC_SUCCESS
        }

        fun authenticate(
            window: FragmentActivity,
            title: String,
            subtitle: String?,
            description: String?,
            cancel: String?,
            onSuccess: () -> Unit,
            onCanceled: () -> Unit,
        ) {
            val executor = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                window.mainExecutor
            } else {
                Executor { command -> Handler().post(command) }
            }

            val builder = BiometricPrompt.PromptInfo.Builder()
                .setTitle(title)
                .setSubtitle(subtitle)
                .setDescription(description)
                .setAllowedAuthenticators(BiometricManager.Authenticators.BIOMETRIC_STRONG)

            builder.setNegativeButtonText(
                cancel ?: LocaleController.getString("Cancel")
            )

            val promptInfo: BiometricPrompt.PromptInfo = builder.build()

            val biometricPrompt =
                BiometricPrompt(
                    window,
                    executor,
                    object : BiometricPrompt.AuthenticationCallback() {
                        override fun onAuthenticationError(
                            errorCode: Int,
                            errString: CharSequence
                        ) {
                            super.onAuthenticationError(errorCode, errString)
                            Logger.d(Logger.LogTag.PASSCODE_CONFIRM, "onAuthenticationError: errorCode=$errorCode")
                            onCanceled()
                        }

                        override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                            super.onAuthenticationSucceeded(result)
                            onSuccess()
                        }

                        override fun onAuthenticationFailed() {
                            super.onAuthenticationFailed()
                            Logger.d(Logger.LogTag.PASSCODE_CONFIRM, "onAuthenticationFailed: Biometric did not match")
                        }
                    })

            biometricPrompt.authenticate(promptInfo)
        }
    }
}
