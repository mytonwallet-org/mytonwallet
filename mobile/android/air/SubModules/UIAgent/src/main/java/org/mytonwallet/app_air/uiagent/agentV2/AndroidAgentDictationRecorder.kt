package org.mytonwallet.app_air.uiagent.agentV2

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaRecorder
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Base64
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

internal class AndroidAgentDictationRecorder(
    context: Context,
    private val onAudioFocusLost: () -> Unit
) : AgentDictationRecorder {
    private val context = context.applicationContext
    private val audioManager = this.context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private var recorder: MediaRecorder? = null
    private var recordingFile: File? = null
    private var audioFocus: AudioFocus? = null

    override fun start() {
        check(recorder == null && recordingFile == null && audioFocus == null)
        try {
            acquireAudioFocus()
            val file = File.createTempFile("agent-dictation-", ".m4a", context.cacheDir)
            recordingFile = file
            val mediaRecorder = createMediaRecorder()
            recorder = mediaRecorder
            mediaRecorder.apply {
                setAudioSource(MediaRecorder.AudioSource.MIC)
                setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
                setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
                setAudioSamplingRate(16_000)
                setAudioChannels(1)
                setAudioEncodingBitRate(32_000)
                setOutputFile(file.absolutePath)
                prepare()
                start()
            }
        } catch (error: Exception) {
            cancel()
            throw error
        }
    }

    override fun amplitude(): Int = recorder?.maxAmplitude ?: 0

    override fun pause() {
        recorder?.pause()
    }

    override fun resume() {
        recorder?.resume()
    }

    override suspend fun finish(): String {
        val mediaRecorder = recorder ?: throw IllegalStateException("audio_unreadable")
        val file = recordingFile ?: throw IllegalStateException("audio_unreadable")
        recorder = null
        recordingFile = null
        try {
            try {
                mediaRecorder.stop()
            } catch (error: Exception) {
                throw IllegalStateException("audio_unreadable", error)
            } finally {
                releaseRecorder(mediaRecorder)
                releaseAudioFocus()
            }
            return withContext(Dispatchers.IO) {
                if (file.length() > MAX_AUDIO_BYTES) {
                    throw IllegalStateException("recording_too_large")
                }
                val bytes = try {
                    file.readBytes()
                } catch (error: Exception) {
                    throw IllegalStateException("audio_unreadable", error)
                }
                if (bytes.isEmpty()) throw IllegalStateException("audio_unreadable")
                Base64.encodeToString(bytes, Base64.NO_WRAP)
            }
        } finally {
            file.delete()
        }
    }

    override fun cancel() {
        val mediaRecorder = recorder
        val file = recordingFile
        recorder = null
        recordingFile = null
        try {
            if (mediaRecorder != null) {
                try {
                    mediaRecorder.stop()
                } catch (_: Exception) {
                    // A cancelled recording may not yet contain a complete AAC frame.
                } finally {
                    releaseRecorder(mediaRecorder)
                }
            }
        } finally {
            releaseAudioFocus()
            file?.delete()
        }
    }

    @Suppress("DEPRECATION")
    private fun createMediaRecorder(): MediaRecorder =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            MediaRecorder(context)
        } else {
            MediaRecorder()
        }

    private fun releaseRecorder(mediaRecorder: MediaRecorder) {
        try {
            mediaRecorder.release()
        } catch (_: Exception) {
            // Cleanup must continue to release audio focus and remove the temporary audio.
        }
    }

    @Suppress("DEPRECATION")
    private fun acquireAudioFocus() {
        val focus = AudioFocus()
        audioFocus = focus
        val result = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                        .build()
                )
                .setOnAudioFocusChangeListener(focus.listener, Handler(Looper.getMainLooper()))
                .build()
            focus.request = request
            audioManager.requestAudioFocus(request)
        } else {
            audioManager.requestAudioFocus(
                focus.listener,
                AudioManager.STREAM_MUSIC,
                AudioManager.AUDIOFOCUS_GAIN_TRANSIENT
            )
        }
        check(result == AudioManager.AUDIOFOCUS_REQUEST_GRANTED) { "audio_unreadable" }
    }

    @Suppress("DEPRECATION")
    private fun releaseAudioFocus() {
        val focus = audioFocus ?: return
        audioFocus = null
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                focus.request?.let(audioManager::abandonAudioFocusRequest)
            } else {
                audioManager.abandonAudioFocus(focus.listener)
            }
        } catch (_: Exception) {
            // Platform cleanup failures must not retain the temporary audio file.
        }
    }

    private inner class AudioFocus {
        var request: AudioFocusRequest? = null
        val listener = AudioManager.OnAudioFocusChangeListener { change ->
            val isLost = change == AudioManager.AUDIOFOCUS_LOSS ||
                change == AudioManager.AUDIOFOCUS_LOSS_TRANSIENT
            if (audioFocus === this && isLost) {
                cancel()
                onAudioFocusLost()
            }
        }
    }

    private companion object {
        const val MAX_AUDIO_BYTES = 1_048_576
    }
}
