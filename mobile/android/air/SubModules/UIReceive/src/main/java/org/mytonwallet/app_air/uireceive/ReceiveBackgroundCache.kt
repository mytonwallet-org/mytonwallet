package org.mytonwallet.app_air.uireceive

import android.graphics.BitmapFactory
import android.graphics.drawable.BitmapDrawable
import android.util.Base64
import androidx.core.graphics.drawable.toDrawable
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.walletbasecontext.utils.ApplicationContextHolder
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod
import kotlin.math.roundToInt

object ReceiveBackgroundCache {
    private data class CacheKey(val chain: MBlockchain, val width: Int, val height: Int)

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val cache = mutableMapOf<CacheKey, BitmapDrawable>()

    fun precache(statusBarTop: Int) {
        val width = ApplicationContextHolder.screenWidth
        val height = statusBarTop + WNavigationBar.DEFAULT_HEIGHT.dp + QRCodeVC.HEIGHT.dp
        for (chain in MBlockchain.supportedChains) {
            render(chain, width, height, null)
        }
    }


    fun render(
        chain: MBlockchain,
        width: Int,
        height: Int,
        callback: ((BitmapDrawable?) -> Unit)?
    ) {
        val key = CacheKey(chain, width, height)

        // Fast path (memory cache)
        cache[key]?.let {
            callback?.invoke(it)
            return
        }

        scope.launch {
            try {
                val result = WalletCore.call(
                    ApiMethod.Other.RenderBlurredReceiveBg(
                        chain = chain,
                        options = ApiMethod.Other.RenderBlurredReceiveBg.Options(
                            width = width,
                            height = height,
                            blurPx = (width / ApplicationContextHolder.density / 2f)
                                .roundToInt()
                                .coerceAtLeast(100),
                            overlay = "rgba(28, 28, 30, 0.25)"
                        )
                    )
                )

                val drawable = result.let { resultUrl ->
                    val base64 = resultUrl.substringAfter("base64,")
                    val bytes = Base64.decode(base64, Base64.DEFAULT)

                    val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                        ?: return@let null

                    bitmap.toDrawable(
                        ApplicationContextHolder.applicationContext.resources
                    ).also {
                        cache[key] = it
                    }
                }

                withContext(Dispatchers.Main) {
                    callback?.invoke(drawable)
                }
            } catch (_: Exception) {
                withContext(Dispatchers.Main) {
                    callback?.invoke(null)
                }
            }
        }
    }
}
