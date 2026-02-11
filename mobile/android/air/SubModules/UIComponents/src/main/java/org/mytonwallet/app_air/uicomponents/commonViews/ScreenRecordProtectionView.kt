package org.mytonwallet.app_air.uicomponents.commonViews

import android.annotation.SuppressLint
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.core.view.setPadding
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WBaseView
import org.mytonwallet.app_air.uicomponents.widgets.WBlurryBackgroundView
import org.mytonwallet.app_air.uicomponents.widgets.WButton
import org.mytonwallet.app_air.uicomponents.widgets.WFrameLayout
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletcontext.helpers.DevicePerformanceClassifier

@SuppressLint("ViewConstructor", "ClickableViewAccessibility")
class ScreenRecordProtectionView(
    val viewController: WViewController,
    val proceedPressed: () -> Unit
) : WFrameLayout(viewController.context) {

    init {
        addBackgroundView()
        addContentView()
        setOnTouchListener { _, _ -> true }
        z = Float.MAX_VALUE
    }

    fun addBackgroundView() {
        if (DevicePerformanceClassifier.isHighClass) {
            addView(
                WBlurryBackgroundView(
                    context,
                    fadeSide = null,
                    overrideBlurRadius = 25f
                ).apply {
                    setupWith(viewController.view)
                },
                ConstraintLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT)
            )
        } else {
            addView(
                WBaseView(context).apply {
                    setBackground(WColor.Background)
                }
            )
        }
    }

    fun addContentView() {
        val contentView = WView(context).apply {
            setPadding(32.dp)
            val titleLabel = WLabel(context).apply {
                setStyle(17f, WFont.SemiBold)
                text = LocaleController.getString("Screen Recording Detected")
                setTextColor(WColor.PrimaryText)
                gravity = Gravity.CENTER
            }
            val descriptionLabel = WLabel(context).apply {
                setStyle(15f, WFont.Regular)
                text = LocaleController.getString("\$screen_recording_info")
                setTextColor(WColor.PrimaryText)
                gravity = Gravity.START
            }
            val proceedButton = WButton(context).apply {
                text = LocaleController.getString("I Understand, Proceed")
                type = WButton.Type.PRIMARY
                setOnClickListener {
                    proceedPressed()
                }
            }
            val goBackButton = WButton(context).apply {
                text = LocaleController.getString("Back")
                type = WButton.Type.SECONDARY
                setOnClickListener {
                    viewController.navigationController?.onBackPressed()
                }
            }
            addView(titleLabel)
            addView(descriptionLabel)
            addView(proceedButton, LayoutParams(MATCH_PARENT, WRAP_CONTENT))
            addView(goBackButton, LayoutParams(MATCH_PARENT, WRAP_CONTENT))
            setConstraints {
                toCenterX(titleLabel)
                toCenterX(descriptionLabel)
                toTop(titleLabel)
                topToBottom(descriptionLabel, titleLabel, 8f)
                topToBottom(proceedButton, descriptionLabel, 16f)
                topToBottom(goBackButton, proceedButton, 8f)
                toBottom(goBackButton)
            }
        }
        addView(contentView, LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
            gravity = Gravity.CENTER
        })
    }
}
