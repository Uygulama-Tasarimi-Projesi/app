package com.example.duygu_analizi

import android.Manifest
import android.content.pm.PackageManager
import android.os.Bundle
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {

    companion object {
        private const val TAG = "MainActivity"
        private const val AUDIO_CHANNEL = "duygu_analizi/audio"
        private const val MIC_PERMISSION_CODE = 101
    }

    private lateinit var audioClassifier: TFLiteAudioClassifier
    private lateinit var audioRecorder: AudioRecorder
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        audioClassifier = TFLiteAudioClassifier(this)
        audioRecorder = AudioRecorder(this)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AUDIO_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {

                    "initializeModel" -> {
                        val success = audioClassifier.initialize()
                        result.success(
                            mapOf(
                                "success" to success,
                                "message" to if (success) "Model hazır" else "Model yüklenemedi"
                            )
                        )
                    }

                    "recordAndClassify" -> {
                        if (!hasMicrophonePermission()) {
                            pendingResult = result
                            requestMicrophonePermission()
                        } else {
                            startRecordingAndClassify(result)
                        }
                    }

                    "startRecording" -> {
                        if (!hasMicrophonePermission()) {
                            pendingResult = result
                            requestMicrophonePermission()
                        } else {
                            val outputFile = getTempAudioFile()
                            audioRecorder.startRecording(
                                outputFile,
                                onComplete = { file ->
                                    // AudioRecorder zaten main thread'e taşıyor
                                    result.success(
                                        mapOf(
                                            "success" to true,
                                            "filePath" to file.absolutePath
                                        )
                                    )
                                },
                                onError = { error ->
                                    result.error("RECORDING_ERROR", error, null)
                                }
                            )
                        }
                    }

                    "stopRecording" -> {
                        audioRecorder.stopRecording()
                        result.success(mapOf("success" to true))
                    }

                    "classifyFile" -> {
                        val filePath = call.argument<String>("filePath")
                        if (filePath == null) {
                            result.error("INVALID_ARGS", "Dosya yolu gerekli", null)
                            return@setMethodCallHandler
                        }
                        classifyAudioFile(File(filePath), result)
                    }

                    "releaseModel" -> {
                        audioClassifier.release()
                        result.success(mapOf("success" to true))
                    }

                    "isRecording" -> {
                        result.success(audioRecorder.isRecording())
                    }

                    "isModelReady" -> {
                        result.success(audioClassifier.isReady())
                    }

                    else -> result.notImplemented()
                }
            }
    }

    private fun startRecordingAndClassify(result: MethodChannel.Result) {
        val outputFile = getTempAudioFile()

        audioRecorder.startRecording(
            outputFile,
            onComplete = { file ->
                // AudioRecorder zaten main thread'e taşıyor — runOnUiThread gereksiz
                Log.d(TAG, "Kayıt tamamlandı, sınıflandırma başlıyor...")
                classifyAudioFile(file, result)
            },
            onError = { error ->
                // AudioRecorder zaten main thread'e taşıyor
                result.error("RECORDING_ERROR", error, null)
            }
        )
    }

    private fun classifyAudioFile(file: File, result: MethodChannel.Result) {
        Thread {
            val prediction = audioClassifier.classifyAudio(file)
            runOnUiThread {
                if (prediction.isError) {
                    result.error("CLASSIFICATION_ERROR", prediction.error, null)
                } else {
                    val probabilitiesMap = TFLiteAudioClassifier.EMOTION_LABELS
                        .mapIndexed { idx, label -> label to prediction.allProbabilities[idx] }
                        .toMap()

                    result.success(
                        mapOf(
                            "emotionLabel" to prediction.emotionLabel,
                            "emotionEmoji" to prediction.emotionEmoji,
                            "confidence" to prediction.confidence,
                            "confidencePercent" to prediction.confidencePercent,
                            "allProbabilities" to probabilitiesMap,
                            "inferenceTimeMs" to prediction.inferenceTimeMs,
                            "topEmotions" to prediction.getTopEmotions(3).map {
                                mapOf("label" to it.first, "probability" to it.second)
                            }
                        )
                    )
                }
            }
        }.start()
    }

    private fun getTempAudioFile(): File {
        return File(cacheDir, "ses_kaydi_${System.currentTimeMillis()}.wav")
    }

    private fun hasMicrophonePermission(): Boolean {
        return ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) ==
                PackageManager.PERMISSION_GRANTED
    }

    private fun requestMicrophonePermission() {
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.RECORD_AUDIO),
            MIC_PERMISSION_CODE
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == MIC_PERMISSION_CODE) {
            if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                Log.d(TAG, "Mikrofon izni verildi")
                pendingResult?.let { startRecordingAndClassify(it) }
            } else {
                pendingResult?.error("PERMISSION_DENIED", "Mikrofon izni gerekli", null)
            }
            pendingResult = null
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        audioRecorder.stopRecording()
        audioClassifier.release()
    }
}