package com.example.duygu_analizi

import android.util.Log
import kotlin.math.*

class SpectrogramExtractor {

    companion object {
        private const val TAG = "SpectrogramExtractor"

        const val N_MELS      = 128
        const val N_FFT       = 2048
        const val HOP_LENGTH  = 512
        const val TARGET_SIZE = 128
        const val SAMPLE_RATE = 16000
    }

    fun extractMelSpectrogram(pcmData: ShortArray): FloatArray {
        Log.d(TAG, "Spektrogram başladı. Örnek sayısı: ${pcmData.size}")

        val floatSamples = FloatArray(pcmData.size) { pcmData[it] / 32768f }

        val stftMagnitudes = computeSTFT(floatSamples)
        val melSpectrogram = applyMelFilterBank(stftMagnitudes)

        // ✅ Eğitimle birebir aynı: her dosya kendi min/max ile normalize
        // Python: mel = (mel - mel_min) / (mel_max - mel_min)
        val normalized = perSampleMinMaxNormalize(melSpectrogram)

        return resizeToTargetSize(normalized, melSpectrogram[0].size)
    }

    // ── STFT ────────────────────────────────────────────────────────────────

    private fun computeSTFT(samples: FloatArray): Array<FloatArray> {
        val numFrames   = maxOf(1, (samples.size - N_FFT) / HOP_LENGTH + 1)
        val spectrogram = Array(N_FFT / 2 + 1) { FloatArray(numFrames) }
        val window      = hannWindow(N_FFT)

        val re = FloatArray(N_FFT)
        val im = FloatArray(N_FFT)

        for (frame in 0 until numFrames) {
            val startIdx = frame * HOP_LENGTH

            for (i in 0 until N_FFT) {
                val s = startIdx + i
                re[i] = if (s < samples.size) samples[s] * window[i] else 0f
                im[i] = 0f
            }

            fftInPlace(re, im)

            for (bin in 0..N_FFT / 2) {
                spectrogram[bin][frame] = re[bin] * re[bin] + im[bin] * im[bin]
            }
        }

        return spectrogram
    }

    private fun fftInPlace(re: FloatArray, im: FloatArray) {
        val n = re.size

        var j = 0
        for (i in 1 until n) {
            var bit = n shr 1
            while (j and bit != 0) { j = j xor bit; bit = bit shr 1 }
            j = j xor bit
            if (i < j) {
                var tmp = re[i]; re[i] = re[j]; re[j] = tmp
                tmp = im[i]; im[i] = im[j]; im[j] = tmp
            }
        }

        var len = 2
        while (len <= n) {
            val halfLen  = len / 2
            val angleStep = (-2.0 * PI / len).toFloat()
            val wRe = cos(angleStep.toDouble()).toFloat()
            val wIm = sin(angleStep.toDouble()).toFloat()

            var i = 0
            while (i < n) {
                var curRe = 1f
                var curIm = 0f
                for (k in 0 until halfLen) {
                    val uRe = re[i + k]
                    val uIm = im[i + k]
                    val vRe = re[i + k + halfLen] * curRe - im[i + k + halfLen] * curIm
                    val vIm = re[i + k + halfLen] * curIm + im[i + k + halfLen] * curRe

                    re[i + k]           = uRe + vRe
                    im[i + k]           = uIm + vIm
                    re[i + k + halfLen] = uRe - vRe
                    im[i + k + halfLen] = uIm - vIm

                    val newCurRe = curRe * wRe - curIm * wIm
                    curIm = curRe * wIm + curIm * wRe
                    curRe = newCurRe
                }
                i += len
            }
            len = len shl 1
        }
    }

    // ── Hann pencere ────────────────────────────────────────────────────────

    private fun hannWindow(size: Int) = FloatArray(size) { n ->
        (0.5 * (1 - cos(2 * PI * n / (size - 1)))).toFloat()
    }

    // ── Mel filtre bankası ───────────────────────────────────────────────────

    private fun applyMelFilterBank(stftMag: Array<FloatArray>): Array<FloatArray> {
        val numFrames = stftMag[0].size
        val melSpec   = Array(N_MELS) { FloatArray(numFrames) }
        val melMin    = hzToMel(0f)
        val melMax    = hzToMel(SAMPLE_RATE / 2f)
        val melPoints = FloatArray(N_MELS + 2) { i ->
            melToHz(melMin + i * (melMax - melMin) / (N_MELS + 1))
        }
        val fftBins = FloatArray(N_MELS + 2) { i ->
            (melPoints[i] / (SAMPLE_RATE / 2f) * (N_FFT / 2)).toInt().toFloat()
        }

        for (m in 0 until N_MELS) {
            val fStart  = fftBins[m].toInt()
            val fCenter = fftBins[m + 1].toInt()
            val fEnd    = fftBins[m + 2].toInt()

            for (frame in 0 until numFrames) {
                var mel = 0f
                if (fCenter > fStart) {
                    for (f in fStart until fCenter) {
                        if (f < stftMag.size)
                            mel += stftMag[f][frame] * (f - fStart).toFloat() / (fCenter - fStart)
                    }
                }
                if (fEnd > fCenter) {
                    for (f in fCenter until fEnd) {
                        if (f < stftMag.size)
                            mel += stftMag[f][frame] * (fEnd - f).toFloat() / (fEnd - fCenter)
                    }
                }
                melSpec[m][frame] = mel
            }
        }
        return melSpec
    }

    private fun hzToMel(hz: Float) = (2595 * log10(1 + hz / 700f))
    private fun melToHz(mel: Float) = (700 * (10f.pow(mel / 2595) - 1))

    // ── Eğitimle birebir aynı normalizasyon ─────────────────────────────────
    // Python kodu: mel = (mel - mel_min) / (mel_max - mel_min)

    private fun perSampleMinMaxNormalize(spec: Array<FloatArray>): Array<FloatArray> {
        var globalMin = Float.MAX_VALUE
        var globalMax = -Float.MAX_VALUE

        for (row in spec) {
            for (v in row) {
                if (v < globalMin) globalMin = v
                if (v > globalMax) globalMax = v
            }
        }

        val range = globalMax - globalMin
        return Array(spec.size) { m ->
            FloatArray(spec[m].size) { f ->
                if (range > 1e-10f) (spec[m][f] - globalMin) / range else 0f
            }
        }
    }

    // ── 128x128 yeniden örnekleme ────────────────────────────────────────────

    private fun resizeToTargetSize(spec: Array<FloatArray>, numFrames: Int): FloatArray {
        val result    = FloatArray(TARGET_SIZE * TARGET_SIZE)
        val melStep   = N_MELS.toFloat()    / TARGET_SIZE
        val frameStep = numFrames.toFloat() / TARGET_SIZE

        for (y in 0 until TARGET_SIZE) {
            for (x in 0 until TARGET_SIZE) {
                val mi = (y * melStep).toInt().coerceIn(0, N_MELS - 1)
                val fi = (x * frameStep).toInt().coerceIn(0, numFrames - 1)
                result[y * TARGET_SIZE + x] = spec[mi][fi]
            }
        }

        Log.d(TAG, "Spektrogram hazır: ${TARGET_SIZE}x${TARGET_SIZE}")
        return result
    }
}