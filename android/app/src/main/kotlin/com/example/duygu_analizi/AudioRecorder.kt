package com.example.duygu_analizi

import android.content.Context
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Handler
import android.os.Looper
import android.util.Log
import java.io.File
import java.io.FileOutputStream
import java.io.IOException

class AudioRecorder(private val context: Context) {

    companion object {
        private const val TAG = "AudioRecorder"
        const val SAMPLE_RATE = 16000
        const val CHANNEL_CONFIG = AudioFormat.CHANNEL_IN_MONO
        const val AUDIO_FORMAT = AudioFormat.ENCODING_PCM_16BIT
        const val RECORDING_DURATION_MS = 3000L
    }

    private var audioRecord: AudioRecord? = null

    // ✅ @Volatile: iki farklı thread (kayıt + timer) bu flag'i okuyor/yazıyor.
    //    Volatile olmadan JVM flag'i cache'leyebilir → stopRecording() etkisiz kalır
    //    → while döngüsü sonlanmaz → UI sonsuza kadar bekler.
    @Volatile private var isRecording = false

    private val mainHandler = Handler(Looper.getMainLooper())

    fun startRecording(
        outputFile: File,
        onComplete: (File) -> Unit,
        onError: (String) -> Unit
    ) {
        if (isRecording) {
            onError("Kayıt zaten devam ediyor")
            return
        }

        val bufferSize = AudioRecord.getMinBufferSize(SAMPLE_RATE, CHANNEL_CONFIG, AUDIO_FORMAT)
            .takeIf { it > 0 } ?: run {
            onError("Ses kaydı başlatılamadı: Geçersiz buffer boyutu")
            return
        }

        try {
            val record = AudioRecord(
                MediaRecorder.AudioSource.MIC,
                SAMPLE_RATE,
                CHANNEL_CONFIG,
                AUDIO_FORMAT,
                bufferSize * 4   // ✅ Daha büyük buffer: read() bloke olma ihtimalini azaltır
            )

            if (record.state != AudioRecord.STATE_INITIALIZED) {
                record.release()
                onError("AudioRecord başlatılamadı")
                return
            }

            audioRecord = record
            isRecording = true
            record.startRecording()

            Log.d(TAG, "Kayıt başladı")

            // ✅ Kayıt thread'i
            Thread {
                writeAudioToFile(
                    record = record,
                    file = outputFile,
                    bufferSize = bufferSize,
                    onComplete = { file -> mainHandler.post { onComplete(file) } },
                    onError = { error -> mainHandler.post { onError(error) } }
                )
            }.start()

            // ✅ Timer thread'i — 3 sn sonra kaydı durdurur
            // Kayıt thread'i zaten başladıktan sonra bu çalışır, race condition yok
            mainHandler.postDelayed({
                Log.d(TAG, "Otomatik durdurma tetiklendi")
                stopRecording()
            }, RECORDING_DURATION_MS)

        } catch (e: SecurityException) {
            onError("Mikrofon izni gerekli: ${e.message}")
        } catch (e: Exception) {
            onError("Kayıt hatası: ${e.message}")
        }
    }

    private fun writeAudioToFile(
        record: AudioRecord,
        file: File,
        bufferSize: Int,
        onComplete: (File) -> Unit,
        onError: (String) -> Unit
    ) {
        val audioBuffer = ShortArray(bufferSize)
        val collectedBytes = mutableListOf<Byte>()

        try {
            // ✅ isRecording = false olduğunda döngü bir sonraki iterasyonda durur.
            //    @Volatile sayesinde bu değişiklik anında görülür.
            while (isRecording) {
                val readCount = record.read(audioBuffer, 0, bufferSize)

                when {
                    readCount > 0 -> {
                        // PCM short → little-endian byte çifti
                        for (i in 0 until readCount) {
                            val s = audioBuffer[i]
                            collectedBytes.add((s.toInt() and 0xFF).toByte())
                            collectedBytes.add((s.toInt() shr 8 and 0xFF).toByte())
                        }
                    }
                    readCount == AudioRecord.ERROR_INVALID_OPERATION -> {
                        // AudioRecord durduruldu — döngüden çık
                        Log.d(TAG, "AudioRecord durduruldu, döngüden çıkılıyor")
                        break
                    }
                    readCount < 0 -> {
                        // Diğer hatalar (ERROR, ERROR_BAD_VALUE vs.)
                        Log.w(TAG, "read() hata kodu: $readCount")
                        break
                    }
                }
            }

            Log.d(TAG, "Toplanan veri: ${collectedBytes.size} byte")

            if (collectedBytes.isEmpty()) {
                onError("Ses verisi alınamadı (boş kayıt)")
                return
            }

            writeWavFile(file, collectedBytes.toByteArray())
            onComplete(file)

        } catch (e: IOException) {
            onError("Dosya yazma hatası: ${e.message}")
        } catch (e: Exception) {
            onError("Kayıt yazma hatası: ${e.message}")
        }
    }

    private fun writeWavFile(file: File, pcmData: ByteArray) {
        FileOutputStream(file).use { fos ->
            val totalDataLen = pcmData.size + 36
            val byteRate = SAMPLE_RATE * 1 * 16 / 8
            fos.write("RIFF".toByteArray())
            fos.write(intToByteArray(totalDataLen))
            fos.write("WAVE".toByteArray())
            fos.write("fmt ".toByteArray())
            fos.write(intToByteArray(16))
            fos.write(shortToByteArray(1))   // PCM
            fos.write(shortToByteArray(1))   // Mono
            fos.write(intToByteArray(SAMPLE_RATE))
            fos.write(intToByteArray(byteRate))
            fos.write(shortToByteArray(2))   // Block align
            fos.write(shortToByteArray(16))  // Bits per sample
            fos.write("data".toByteArray())
            fos.write(intToByteArray(pcmData.size))
            fos.write(pcmData)
        }
        Log.d(TAG, "WAV kaydedildi: ${file.absolutePath} (${file.length()} byte)")
    }

    fun stopRecording() {
        if (!isRecording) return
        isRecording = false          // ✅ @Volatile → kayıt thread'i anında görür

        try {
            audioRecord?.stop()      // read() ERROR_INVALID_OPERATION döndürmeye başlar
            audioRecord?.release()
        } catch (e: Exception) {
            Log.w(TAG, "stopRecording hatası: ${e.message}")
        } finally {
            audioRecord = null
        }

        Log.d(TAG, "Kayıt durduruldu")
    }

    fun isRecording(): Boolean = isRecording

    private fun intToByteArray(value: Int): ByteArray = byteArrayOf(
        (value and 0xFF).toByte(),
        (value shr 8 and 0xFF).toByte(),
        (value shr 16 and 0xFF).toByte(),
        (value shr 24 and 0xFF).toByte()
    )

    private fun shortToByteArray(value: Int): ByteArray = byteArrayOf(
        (value and 0xFF).toByte(),
        (value shr 8 and 0xFF).toByte()
    )
}