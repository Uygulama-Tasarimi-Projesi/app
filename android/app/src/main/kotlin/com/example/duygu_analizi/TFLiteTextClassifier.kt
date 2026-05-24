package com.example.duygu_analizi

import android.content.Context
import android.util.Log
import io.flutter.FlutterInjector
import org.tensorflow.lite.Interpreter
import java.io.FileInputStream
import java.nio.MappedByteBuffer
import java.nio.channels.FileChannel

class TFLiteTextClassifier(private val context: Context) {
    private var interpreter: Interpreter? = null

    init {
        try {
            val options = Interpreter.Options()
            val loader = FlutterInjector.instance().flutterLoader()
            val key = loader.getLookupKeyForAsset("assets/models/en_iyi_metin_modeli.tflite")
            
            interpreter = Interpreter(loadModelFile(context, key), options)
            println("Metin modeli Kotlin tarafında başarıyla yüklendi!")
        } catch (e: Exception) {
            println("Metin modeli yüklenirken hata: ${e.message}")
        }
    }

    private fun loadModelFile(context: Context, assetPath: String): MappedByteBuffer {
        val fileDescriptor = context.assets.openFd(assetPath)
        val inputStream = FileInputStream(fileDescriptor.fileDescriptor)
        val fileChannel = inputStream.channel
        val startOffset = fileDescriptor.startOffset
        val declaredLength = fileDescriptor.declaredLength
        return fileChannel.map(FileChannel.MapMode.READ_ONLY, startOffset, declaredLength)
    }

    fun classify(sequence: IntArray): FloatArray? {
        if (interpreter == null) return null

        val inputTensor = interpreter?.getInputTensor(0)
        Log.d("TFLite", "Input dtype: ${inputTensor?.dataType()}, shape: ${inputTensor?.shape()?.toList()}")
        
        // ÇÖZÜM: Loglar modelin FLOAT32 beklediğini söylüyor. 
        // Gelen IntArray'i FloatArray'e çeviriyoruz.
        val floatSequence = FloatArray(sequence.size) { sequence[it].toFloat() }
        val input = Array(1) { floatSequence }

        // Çıkış şekli [1, 7] (7 duygu olasılığı)
        val output = Array(1) { FloatArray(7) }

        try {
            interpreter?.run(input, output)
            return output[0]
        } catch (e: Exception) {
            Log.e("TFLite", "Çıkarım (inference) hatası: ${e.message}")
            return null
        }
    }

    fun close() {
        interpreter?.close()
        interpreter = null
    }
}