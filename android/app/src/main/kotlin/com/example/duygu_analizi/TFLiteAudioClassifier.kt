package com.example.duygu_analizi

import android.content.Context
import android.util.Log
import org.tensorflow.lite.Interpreter
import java.io.FileInputStream
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.MappedByteBuffer
import java.nio.channels.FileChannel

class TFLiteAudioClassifier(private val context: Context) {

    companion object {
        private const val TAG = "TFLiteAudioClassifier"
        private const val MODEL_FILE = "en_iyi_ses_modeli.tflite"

        val EMOTION_LABELS = arrayOf(
            "Mutlu", "Nötr", "Üzgün", "Öfkeli", "İğrenme", "Korku", "Şaşkınlık"
        )

        val EMOTION_EMOJIS = arrayOf("😊", "😐", "😢", "😡", "🤢", "😨", "😲")

        private const val INPUT_SIZE = 128
        private const val NUM_CLASSES = 7
        private const val FLOAT_SIZE = 4
    }

    private var interpreter: Interpreter? = null
    private val spectrogramExtractor = SpectrogramExtractor()
    private var isInitialized = false

    /**
     * Modeli yükler ve Interpreter'ı başlatır.
     * DÜZELTME: return'den sonraki unreachable kod bloğu kaldırıldı.
     * O blok modelin hiç yüklenmemesine yol açıyor, ses kaydı tıkanıyordu.
     */
    fun initialize(): Boolean {
        // ✅ Assets içeriğini önce logla (artık return'den önce)
        try {
            val assetList = context.assets.list("")?.joinToString()
            Log.d(TAG, "Assets kontrol ediliyor: $assetList")
        } catch (e: Exception) {
            Log.w(TAG, "Assets listelenemedi: ${e.message}")
        }

        return try {
            val modelBuffer = loadModelFromAssets()
            val options = Interpreter.Options().apply {
                numThreads = 2
                useNNAPI = false
            }
            interpreter = Interpreter(modelBuffer, options)
            isInitialized = true
            Log.d(TAG, "TFLite ses modeli başarıyla yüklendi")
            true
        } catch (e: Exception) {
            Log.e(TAG, "Model yükleme hatası: ${e.message}", e)
            isInitialized = false
            false
        }
        // ❌ ESKİ KOD: Burada Log.d ve assetList satırları vardı — return'den
        //    sonra geldikleri için hiç çalışmıyor, Kotlin bunu unreachable
        //    code olarak işaretler. initialize() her zaman false dönüyordu.
    }

    private fun loadModelFromAssets(): MappedByteBuffer {
        val assetFileDescriptor = context.assets.openFd(MODEL_FILE)
        val inputStream = FileInputStream(assetFileDescriptor.fileDescriptor)
        val fileChannel = inputStream.channel
        val startOffset = assetFileDescriptor.startOffset
        val declaredLength = assetFileDescriptor.declaredLength
        return fileChannel.map(FileChannel.MapMode.READ_ONLY, startOffset, declaredLength)
    }

    fun classifyAudio(wavFile: File): AudioPredictionResult {
        if (!isInitialized) {
            return AudioPredictionResult(
                error = "Model başlatılmamış",
                emotionLabel = "Hata",
                confidence = 0f,
                allProbabilities = FloatArray(NUM_CLASSES)
            )
        }

        return try {
            val pcmData = readWavAsPcm(wavFile)
            Log.d(TAG, "PCM verisi okundu: ${pcmData.size} örnek")

            val spectrogramData = spectrogramExtractor.extractMelSpectrogram(pcmData)
            Log.d(TAG, "Spektrogram hazır: ${spectrogramData.size} değer")

            val inputBuffer = prepareInputBuffer(spectrogramData)
            val outputBuffer = Array(1) { FloatArray(NUM_CLASSES) }

            val startTime = System.currentTimeMillis()
            interpreter?.run(inputBuffer, outputBuffer)
            val inferenceTime = System.currentTimeMillis() - startTime
            Log.d(TAG, "Çıkarım süresi: ${inferenceTime}ms")

            val probabilities = outputBuffer[0]
            val maxIdx = probabilities.indices.maxByOrNull { probabilities[it] } ?: 0
            val maxProb = probabilities[maxIdx]

            Log.d(TAG, "Tahmin: ${EMOTION_LABELS[maxIdx]} (%.2f%%)".format(maxProb * 100))

            AudioPredictionResult(
                emotionLabel = EMOTION_LABELS[maxIdx],
                emotionEmoji = EMOTION_EMOJIS[maxIdx],
                confidence = maxProb,
                allProbabilities = probabilities,
                inferenceTimeMs = inferenceTime,
                error = null
            )

        } catch (e: Exception) {
            Log.e(TAG, "Sınıflandırma hatası: ${e.message}")
            AudioPredictionResult(
                error = "Analiz hatası: ${e.message}",
                emotionLabel = "Hata",
                confidence = 0f,
                allProbabilities = FloatArray(NUM_CLASSES)
            )
        }
    }

    private fun readWavAsPcm(wavFile: File): ShortArray {
        val bytes = wavFile.readBytes()
        val dataStart = 44
        val numSamples = (bytes.size - dataStart) / 2

        return ShortArray(numSamples) { i ->
            val byteIdx = dataStart + i * 2
            ((bytes[byteIdx + 1].toInt() shl 8) or (bytes[byteIdx].toInt() and 0xFF)).toShort()
        }
    }

    private fun prepareInputBuffer(spectrogramData: FloatArray): ByteBuffer {
        val bufferSize = 1 * INPUT_SIZE * INPUT_SIZE * 1 * FLOAT_SIZE
        val buffer = ByteBuffer.allocateDirect(bufferSize)
        buffer.order(ByteOrder.nativeOrder())
        spectrogramData.forEach { value -> buffer.putFloat(value) }
        buffer.rewind()
        return buffer
    }

    fun release() {
        interpreter?.close()
        interpreter = null
        isInitialized = false
        Log.d(TAG, "TFLite ses modeli serbest bırakıldı")
    }

    fun isReady(): Boolean = isInitialized
}

data class AudioPredictionResult(
    val emotionLabel: String,
    val emotionEmoji: String = "❓",
    val confidence: Float,
    val allProbabilities: FloatArray,
    val inferenceTimeMs: Long = 0L,
    val error: String? = null
) {
    val isError: Boolean get() = error != null
    val confidencePercent: Int get() = (confidence * 100).toInt()

    fun getTopEmotions(topN: Int = 3): List<Pair<String, Float>> {
        return allProbabilities.indices
            .sortedByDescending { allProbabilities[it] }
            .take(topN)
            .map { TFLiteAudioClassifier.EMOTION_LABELS[it] to allProbabilities[it] }
    }
}