package org.mytonwallet.app_air.sqscan.screen

import android.Manifest
import android.app.Dialog
import android.content.Context
import android.content.DialogInterface
import android.content.pm.PackageManager
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.Toast
import androidx.core.content.ContextCompat
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import org.mytonwallet.app_air.uicomponents.base.WWindow
import org.mytonwallet.app_air.walletcontext.helpers.CustomLifecycleOwner

class QrScannerDialog private constructor(
    private val context: Context,
    private val listener: QrScannerListener
) : Dialog(context), DialogInterface.OnDismissListener, QrScannerListener {
    private val lifecycleOwner = CustomLifecycleOwner()
    private val qrScannerView by lazy { QrScannerView(context) }

    companion object {
        fun build(context: Context, listener: (String) -> Unit): QrScannerDialog {
            return build(context, object : QrScannerListener {
                override fun onQrScanComplete(qrCode: String) {
                    listener.invoke(qrCode)
                }
            })
        }

        fun build(context: Context, listener: QrScannerListener): QrScannerDialog {
            return QrScannerDialog(context, listener).apply {
                setCanceledOnTouchOutside(false)
                setCancelable(true)
            }
        }
    }

    override fun show() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val permission = ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA)
            if (permission != PackageManager.PERMISSION_GRANTED) {
                val activity = context as? WWindow ?: return
                activity.requestPermissions(arrayOf(Manifest.permission.CAMERA)) { _, grantResults ->
                    if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                        super.show()
                    } else {
                        // todo show dialog
                        Toast.makeText(context, "No camera permission", Toast.LENGTH_LONG).show()
                    }
                }
                return
            }
        }

        super.show()
    }

    private var qrScanResult: String? = null
    override fun onQrScanValidate(qrCode: String): Boolean {
        return listener.onQrScanValidate(qrCode)
    }

    override fun onQrScanComplete(qrCode: String) {
        qrScanResult = qrCode
        listener.onQrScanComplete(qrCode)
        dismiss()
    }

    override fun onQrScanCancel() {
        dismiss()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        qrScannerView.init(lifecycleOwner, this)
        qrScannerView.clipToPadding = false
        setContentView(
            qrScannerView,
            ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        )

        val window = window ?: return

        window.setBackgroundDrawableResource(android.R.color.transparent)
        window.setLayout(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT
        )

        window.attributes.apply {
            width = ViewGroup.LayoutParams.MATCH_PARENT
            height = ViewGroup.LayoutParams.MATCH_PARENT

            flags = flags and WindowManager.LayoutParams.FLAG_DIM_BEHIND.inv()
            flags = flags or (WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_LAYOUT_INSET_DECOR or
                WindowManager.LayoutParams.FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS)

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                layoutInDisplayCutoutMode =
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            }
        }

        window.navigationBarColor = Color.TRANSPARENT
        window.statusBarColor = Color.TRANSPARENT
        window.decorView.systemUiVisibility =
            View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
                View.SYSTEM_UI_FLAG_LAYOUT_STABLE

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            window.decorView.systemUiVisibility =
                window.decorView.systemUiVisibility or View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            window.decorView.systemUiVisibility =
                window.decorView.systemUiVisibility and View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR.inv()
        }

        ViewCompat.setOnApplyWindowInsetsListener(window.decorView) { _, insets ->
            val systemBars =
                insets.getInsets(WindowInsetsCompat.Type.displayCutout() or WindowInsetsCompat.Type.systemBars())
            qrScannerView.setPadding(
                systemBars.left,
                systemBars.top,
                systemBars.right,
                systemBars.bottom
            )
            WindowInsetsCompat.CONSUMED
        }
    }

    override fun onStart() {
        super.onStart()
        lifecycleOwner.start()
        lifecycleOwner.resume()
    }

    override fun onStop() {
        super.onStop()
        lifecycleOwner.resume()
        lifecycleOwner.stop()
    }


    /* Dismiss */

    private var dismissListener: DialogInterface.OnDismissListener? = null
    override fun setOnDismissListener(listener: DialogInterface.OnDismissListener?) {
        dismissListener = listener
        super.setOnDismissListener(this)
    }

    init {
        super.setOnDismissListener(this)
    }

    override fun onDismiss(dialog: DialogInterface?) {
        lifecycleOwner.destroy()
        if (qrScanResult == null) {
            listener.onQrScanCancel()
        }
        dismissListener?.onDismiss(this)
    }
}
