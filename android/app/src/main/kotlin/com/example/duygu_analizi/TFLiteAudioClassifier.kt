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
            "Mutlu", "Notr", "Uzgun", "Ofkeli", "Igrenme", "Korku", "Saskinlik"
        )

        val EMOTION_EMOJIS = arrayOf(
            "\uD83D\uDE0A", // Mutlu
            "\uD83D\uDE10", // Notr
            "\uD83D\uDE22", // Uzgun
            "\uD83D\uDE21", // Ofkeli
            "\uD83E\uDD22", // Igrenme
            "\uD83D\uDE28", // Korku
            "\uD83D\uDE32"  // Saskinlik
        )

        private const val INPUT_SIZE  = 128
        private const val NUM_CLASSES = 7
        private const val FLOAT_SIZE  = 4
    }

    private var interpreter: Interpreter? = null
    private val spectrogramExtractor = SpectrogramExtractor()
    private var isInitialized = false

    fun initialize(): Boolean {
        try {
            val assetList = context.assets.list("")?.joinToString()
            Log.d(TAG, "Assets: $assetList")
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
            Log.d(TAG, "TFLite ses modeli yuklendi")
            true
        } catch (e: Exception) {
            Log.e(TAG, "Model yukleme hatasi: ${e.message}", e)
            isInitialized = false
            false
        }
    }

    private fun loadModelFromAssets(): MappedByteBuffer {
        val afd = context.assets.openFd(MODEL_FILE)
        val inputStream = FileInputStream(afd.fileDescriptor)
        val fileChannel = inputStream.channel
        return fileChannel.map(FileChannel.MapMode.READ_ONLY, afd.startOffset, afd.declaredLength)
    }

    fun classifyAudio(wavFile: File): AudioPredictionResult {
        if (!isInitialized) {
            return AudioPredictionResult(
                error = "Model baslatilmamis",
                emotionLabel = "Hata",
                confidence = 0f,
                allProbabilities = FloatArray(NUM_CLASSES)
            )
        }

        return try {
            val pcmData = readWavAsPcm(wavFile)
            Log.d(TAG, "PCM: ${pcmData.size} ornek")

            val spectrogramData = spectrogramExtractor.extractMelSpectrogram(pcmData)
            Log.d(TAG, "Spektrogram: ${spectrogramData.size} deger")

            val inputBuffer  = prepareInputBuffer(spectrogramData)
            val outputBuffer = Array(1) { FloatArray(NUM_CLASSES) }

            val startTime = System.currentTimeMillis()
            interpreter?.run(inputBuffer, outputBuffer)
            val inferenceTime = System.currentTimeMillis() - startTime
            Log.d(TAG, "Cikarim: ${inferenceTime}ms")

            val probabilities = outputBuffer[0]
            val maxIdx  = probabilities.indices.maxByOrNull { probabilities[it] } ?: 0
            val maxProb = probabilities[maxIdx]

            Log.d(TAG, "Tum olasiliklar: ${probabilities.mapIndexed { i, p -> "${EMOTION_LABELS[i]}=%.3f".format(p) }}")

            AudioPredictionResult(
                emotionLabel     = EMOTION_LABELS[maxIdx],
                emotionEmoji     = EMOTION_EMOJIS[maxIdx],
                confidence       = maxProb,
                allProbabilities = probabilities,
                inferenceTimeMs  = inferenceTime,
                error            = null
            )
        } catch (e: Exception) {
            Log.e(TAG, "Siniflandirma hatasi: ${e.message}")
            AudioPredictionResult(
                error            = "Analiz hatasi: ${e.message}",
                emotionLabel     = "Hata",
                confidence       = 0f,
                allProbabilities = FloatArray(NUM_CLASSES)
            )
        }
    }
    private fun readWavAsPcm(wavFile: File): ShortArray {
        val bytes = wavFile.readBytes()
        var dataStart = 44  // varsayılan, bulamazsa kullanılır
        for (i in 12 until bytes.size - 4) {
            if (bytes[i]   == 'd'.code.toByte() &&
                bytes[i+1] == 'a'.code.toByte() &&
                bytes[i+2] == 't'.code.toByte() &&
                bytes[i+3] == 'a'.code.toByte()) {
                dataStart = i + 8  // "data"(4) + chunk size(4) = 8 byte sonrası
                break
            }
        }

        Log.d(TAG, "WAV data baslangici: $dataStart (dosya: ${bytes.size} byte)")

        val numSamples = (bytes.size - dataStart) / 2
        return ShortArray(numSamples) { i ->
            val idx = dataStart + i * 2
            ((bytes[idx + 1].toInt() shl 8) or (bytes[idx].toInt() and 0xFF)).toShort()
        }
    }

    private fun prepareInputBuffer(spectrogramData: FloatArray): ByteBuffer {
        val bufferSize = INPUT_SIZE * INPUT_SIZE * FLOAT_SIZE
        val buffer = ByteBuffer.allocateDirect(bufferSize)
        buffer.order(ByteOrder.nativeOrder())
        spectrogramData.forEach { buffer.putFloat(it) }
        buffer.rewind()
        return buffer
    }

    fun release() {
        interpreter?.close()
        interpreter = null
        isInitialized = false
        Log.d(TAG, "TFLite modeli serbest birakildi")
    }

    fun isReady(): Boolean = isInitialized
}

data class AudioPredictionResult(
    val emotionLabel: String,
    val emotionEmoji: String = "?",
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