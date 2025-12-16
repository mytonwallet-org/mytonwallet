package org.mytonwallet.app_air.walletcontext.helpers

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.drawable.BitmapDrawable
import android.net.Uri
import android.os.Build
import android.text.TextUtils
import android.widget.ImageView
import androidx.core.content.FileProvider
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import java.io.File
import java.io.FileOutputStream

class ShareHelpers {
    companion object {

        fun shareQRImage(activity: Activity, imageView: ImageView, text: String) {
            try {
                val bitmapDrawable = imageView.drawable as BitmapDrawable
                var f = File(activity.cacheDir, "sharing/")
                f.mkdirs()
                f = File(f, "qr.jpg")
                val outputStream = FileOutputStream(f.absolutePath)
                bitmapDrawable.bitmap.compress(Bitmap.CompressFormat.JPEG, 87, outputStream)
                outputStream.close()

                val intent = Intent(Intent.ACTION_SEND)
                intent.setType("image/jpeg")
                if (!TextUtils.isEmpty(text)) {
                    intent.putExtra(Intent.EXTRA_TEXT, text)
                }
                if (Build.VERSION.SDK_INT >= 24) {
                    try {
                        intent.putExtra(
                            Intent.EXTRA_STREAM,
                            FileProvider.getUriForFile(
                                activity,
                                activity.packageName + ".provider",
                                f
                            )
                        )
                        intent.setFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    } catch (ignore: Exception) {
                        intent.putExtra(Intent.EXTRA_STREAM, Uri.fromFile(f))
                    }
                } else {
                    intent.putExtra(Intent.EXTRA_STREAM, Uri.fromFile(f))
                }
                activity.startActivityForResult(
                    Intent.createChooser(
                        intent,
                        LocaleController.getString("Share QR Code")
                    ), 500
                )
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }

        fun shareText(context: Context, text: String, title: String) {
            val shareIntent = Intent(Intent.ACTION_SEND).apply {
                setType("text/plain")
                putExtra(Intent.EXTRA_TEXT, text)
            }
            context.startActivity(Intent.createChooser(shareIntent, title))
        }
    }
}
