package org.mytonwallet.app_air.walletcontext.helpers

import android.content.Context
import android.media.AudioManager
import android.media.MediaPlayer

class AudioHelpers {

    enum class Sound(val fileName: String) {
        IncomingTransaction("incoming-transaction.mp3")
    }

    companion object {
        private var player: MediaPlayer? = null

        fun play(context: Context, sound: Sound) {
            val audioManager =
                context.getSystemService(Context.AUDIO_SERVICE) as AudioManager

            if (audioManager.ringerMode != AudioManager.RINGER_MODE_NORMAL) {
                return
            }

            val afd = context.assets.openFd(sound.fileName)
            player = MediaPlayer().apply {
                setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
                prepare()
                start()
            }
        }
    }
}
