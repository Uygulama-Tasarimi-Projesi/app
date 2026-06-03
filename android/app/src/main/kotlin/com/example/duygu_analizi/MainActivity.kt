package com.example.duygu_analizi

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity: FlutterActivity() {
    private val TEXT_CHANNEL = "com.example.duygu_analizi/text_model"
    private val AUDIO_CHANNEL = "com.example.duygu_analizi/audio_channel"
    
    private var textClassifier: TFLiteTextClassifier? = null
    private var audioClassifier: TFLiteAudioClassifier? = null
    private var audioRecorder: AudioRecorder? = null
    private var recordedFile: File? = null
    private var pendingRecordResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        textClassifier = TFLiteTextClassifier(context)
        audioClassifier = TFLiteAudioClassifier(context)
        audioClassifier?.initialize()
        audioRecorder = AudioRecorder(context)

        //METİN KANALI 
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, TEXT_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "classifyText") {
                val inputSeq = call.argument<List<Int>>("sequence")
                if (inputSeq != null) {
                    val probs = textClassifier?.classify(inputSeq.toIntArray())
                    if (probs != null) {
                        result.success(probs.map { it.toDouble() })
                    } else {
                        result.error("INFERENCE_ERROR", "Metin modeli çalıştırılamadı", null)
                    }
                } else {
                    result.error("INVALID_INPUT", "Geçersiz giriş dizisi", null)
                }
            } else {
                result.notImplemented()
            }
        }

        // SES KANALI
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AUDIO_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "initializeModel" -> {
                    result.success(mapOf("success" to true))
                }
                "isModelReady" -> {
                    result.success(audioClassifier != null)
                }
                "releaseModel" -> {
                    audioClassifier?.release()
                    result.success(true)
                }
                "startRecording" -> {
                    pendingRecordResult = result 
                    
                    val fileName = "temp_audio_record.wav"
                    recordedFile = File(context.cacheDir, fileName)
                    
                    audioRecorder?.startRecording(
                        outputFile = recordedFile!!,
                        onComplete = { file ->
                            println("Kayıt tamamlandı, dosya oluşturuldu: ${file.absolutePath}")
                            pendingRecordResult?.success(mapOf("success" to true, "filePath" to file.absolutePath))
                            pendingRecordResult = null
                        },
                        onError = { error ->
                            println("Kayıt Hatası: $error")
                            pendingRecordResult?.success(mapOf("success" to false, "error" to error))
                            pendingRecordResult = null
                        }
                    )
                }
                "stopRecording" -> {
                    audioRecorder?.stopRecording()
                    result.success(null)
                }
                "classifyFile" -> {
                    val filePath = call.argument<String>("filePath")
                    val fileToClassify = if (filePath != null) File(filePath) else recordedFile

                    if (fileToClassify != null && fileToClassify.exists()) {
                        val prediction = audioClassifier?.classifyAudio(fileToClassify)
                        
                        if (prediction != null && !prediction.isError) {
                            val response = mapOf(
                                "label" to prediction.emotionLabel,
                                "emoji" to prediction.emotionEmoji,
                                "confidence" to prediction.confidence,
                                "allProbabilities" to prediction.allProbabilities.map { it.toDouble() }
                            )
                            result.success(response)
                        } else {
                            result.error("INFERENCE_ERROR", prediction?.error ?: "Ses modeli çalıştırılamadı", null)
                        }
                    } else {
                        result.error("FILE_ERROR", "Kaydedilmiş ses dosyası bulunamadı", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        textClassifier?.close()
        audioClassifier?.release()
        audioRecorder?.stopRecording()
        super.onDestroy()
    }
}