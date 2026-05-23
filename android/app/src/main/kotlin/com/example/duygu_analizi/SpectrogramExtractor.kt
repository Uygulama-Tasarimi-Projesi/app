package com.example.duygu_analizi

import android.util.Log
import kotlin.math.*

/**
 * 14. Hafta - Mel-Spektrogram Çıkarıcı
 * Ham PCM ses verisinden 128x128 Mel-Spektrogram matrisi üretir.
 * 13. haftada eğitilen CNN modelinin beklediği giriş formatına uygun.
 */
class SpectrogramExtractor {

    companion object {
        private const val TAG = "SpectrogramExtractor"

        // Model parametreleri (13. haftadan gelen)
        const val N_MELS = 128          // Mel filtre sayısı
        const val N_FFT = 2048          // FFT pencere boyutu
        const val HOP_LENGTH = 512      // Çerçeveler arası adım
        const val TARGET_SIZE = 128     // Hedef boyut (128x128)
        const val SAMPLE_RATE = 16000   // Hz
        const val MIN_DB = -80f         // Min-Max scaling için minimum dB
        const val MAX_DB = 0f           // Min-Max scaling için maksimum dB
    }

    /**
     * PCM ses verisinden normalize edilmiş Mel-Spektrogram float dizisi üretir.
     * @param pcmData 16-bit PCM ses örnekleri
     * @return 128x128x1 float array (CNN girişi)
     */
    fun extractMelSpectrogram(pcmData: ShortArray): FloatArray {
        Log.d(TAG, "Spektrogram çıkarma başladı. Örnek sayısı: ${pcmData.size}")

        // Float'a dönüştür ve normalize et [-1, 1]
        val floatSamples = FloatArray(pcmData.size) { pcmData[it] / 32768f }

        // STFT (Kısa Zaman Fourier Dönüşümü)
        val stftMagnitudes = computeSTFT(floatSamples)

        // Mel filtre bankası uygula
        val melSpectrogram = applyMelFilterBank(stftMagnitudes)

        // Güç → dB dönüşümü
        val dbSpectrogram = powerToDb(melSpectrogram)

        // Min-Max normalizasyon [0, 1]
        val normalized = minMaxNormalize(dbSpectrogram)

        // 128x128 boyutuna yeniden örnekle
        return resizeToTargetSize(normalized, melSpectrogram[0].size)
    }

    /**
     * Kısa Zaman Fourier Dönüşümü
     */
    private fun computeSTFT(samples: FloatArray): Array<FloatArray> {
        val numFrames = (samples.size - N_FFT) / HOP_LENGTH + 1
        val spectrogram = Array(N_FFT / 2 + 1) { FloatArray(numFrames) }

        val window = hannWindow(N_FFT)

        for (frame in 0 until numFrames) {
            val startIdx = frame * HOP_LENGTH
            val frameData = FloatArray(N_FFT)

            // Pencere uygula
            for (i in 0 until N_FFT) {
                val sampleIdx = startIdx + i
                frameData[i] = if (sampleIdx < samples.size) samples[sampleIdx] * window[i] else 0f
            }

            // FFT hesapla
            val fftResult = computeFFT(frameData)

            // Büyüklük hesapla
            for (bin in 0..N_FFT / 2) {
                val real = fftResult[2 * bin]
                val imag = fftResult[2 * bin + 1]
                spectrogram[bin][frame] = real * real + imag * imag // Güç spektrumu
            }
        }

        return spectrogram
    }

    /**
     * Hann pencere fonksiyonu
     */
    private fun hannWindow(size: Int): FloatArray {
        return FloatArray(size) { n ->
            (0.5 * (1 - cos(2 * PI * n / (size - 1)))).toFloat()
        }
    }

    /**
     * Basitleştirilmiş FFT (Cooley-Tukey)
     */
    private fun computeFFT(data: FloatArray): FloatArray {
        val n = data.size
        val result = FloatArray(n * 2)

        // DFT (basit implementasyon - gerçek projede Apache Commons Math kullanılabilir)
        for (k in 0 until n / 2 + 1) {
            var real = 0f
            var imag = 0f
            for (t in 0 until n) {
                val angle = 2 * PI * k * t / n
                real += data[t] * cos(angle).toFloat()
                imag -= data[t] * sin(angle).toFloat()
            }
            result[2 * k] = real
            result[2 * k + 1] = imag
        }

        return result
    }

    /**
     * Mel filtre bankası uygulama
     * 128 adet Mel filtresi kullanılır
     */
    private fun applyMelFilterBank(stftMagnitudes: Array<FloatArray>): Array<FloatArray> {
        val numFrames = stftMagnitudes[0].size
        val melSpectrogram = Array(N_MELS) { FloatArray(numFrames) }

        // Mel frekansları
        val melMin = hzToMel(0f)
        val melMax = hzToMel(SAMPLE_RATE / 2f)
        val melPoints = FloatArray(N_MELS + 2) { i ->
            melToHz(melMin + i * (melMax - melMin) / (N_MELS + 1))
        }

        // Hz → FFT bin dönüşümü
        val fftBins = FloatArray(N_MELS + 2) { i ->
            (melPoints[i] / (SAMPLE_RATE / 2f) * (N_FFT / 2)).toInt().toFloat()
        }

        // Filtre uygula
        for (m in 0 until N_MELS) {
            val fStart = fftBins[m].toInt()
            val fCenter = fftBins[m + 1].toInt()
            val fEnd = fftBins[m + 2].toInt()

            for (frame in 0 until numFrames) {
                var melValue = 0f

                // Yükselen eğim
                for (f in fStart until fCenter) {
                    if (f < stftMagnitudes.size && fCenter > fStart) {
                        melValue += stftMagnitudes[f][frame] * (f - fStart).toFloat() / (fCenter - fStart)
                    }
                }

                // Düşen eğim
                for (f in fCenter until fEnd) {
                    if (f < stftMagnitudes.size && fEnd > fCenter) {
                        melValue += stftMagnitudes[f][frame] * (fEnd - f).toFloat() / (fEnd - fCenter)
                    }
                }

                melSpectrogram[m][frame] = melValue
            }
        }

        return melSpectrogram
    }

    private fun hzToMel(hz: Float): Float = 2595 * log10(1 + hz / 700f)
    private fun melToHz(mel: Float): Float = 700 * (10f.pow(mel / 2595) - 1)

    /**
     * Güç spektrumunu dB'e dönüştür
     */
    private fun powerToDb(spectrogram: Array<FloatArray>): Array<FloatArray> {
        return Array(spectrogram.size) { mel ->
            FloatArray(spectrogram[mel].size) { frame ->
                val power = spectrogram[mel][frame]
                if (power > 1e-10f) 10 * log10(power) else MIN_DB
            }
        }
    }

    /**
     * Min-Max normalizasyon: [-80dB, 0dB] → [0, 1]
     */
    private fun minMaxNormalize(spectrogram: Array<FloatArray>): Array<FloatArray> {
        return Array(spectrogram.size) { mel ->
            FloatArray(spectrogram[mel].size) { frame ->
                val db = spectrogram[mel][frame].coerceIn(MIN_DB, MAX_DB)
                (db - MIN_DB) / (MAX_DB - MIN_DB)
            }
        }
    }

    /**
     * Spektrogramı 128x128 boyutuna yeniden örnekle
     * @return Düzleştirilmiş FloatArray (128*128)
     */
    private fun resizeToTargetSize(spectrogram: Array<FloatArray>, numFrames: Int): FloatArray {
        val result = FloatArray(TARGET_SIZE * TARGET_SIZE)
        val melStep = N_MELS.toFloat() / TARGET_SIZE
        val frameStep = numFrames.toFloat() / TARGET_SIZE

        for (y in 0 until TARGET_SIZE) {
            for (x in 0 until TARGET_SIZE) {
                val melIdx = (y * melStep).toInt().coerceIn(0, N_MELS - 1)
                val frameIdx = (x * frameStep).toInt().coerceIn(0, numFrames - 1)
                result[y * TARGET_SIZE + x] = spectrogram[melIdx][frameIdx]
            }
        }

        Log.d(TAG, "Spektrogram hazır: ${TARGET_SIZE}x${TARGET_SIZE}")
        return result
    }
}