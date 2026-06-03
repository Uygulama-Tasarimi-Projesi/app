import 'package:flutter/services.dart';

class NativeAudioChannel {
  static const MethodChannel _channel = MethodChannel('com.example.duygu_analizi/audio_channel');

  Future<bool> initializeModel() async {
    try {
      final result = await _channel.invokeMethod<Map>('initializeModel');
      return result?['success'] == true;
    } catch (e) {
      print('initializeModel hatası: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>> startRecording() async {
    try {
      final result = await _channel.invokeMethod<Map>('startRecording');
      if (result == null) return _error('Sonuç alınamadı');
      if (result['success'] != true) {
        return _error(result['error']?.toString() ?? 'Kayıt başlatılamadı');
      }
      return {
        'success': true,
        'filePath': result['filePath'] as String,
      };
    } on PlatformException catch (e) {
      return _error('Platform hatası: ${e.message}');
    } catch (e) {
      return _error('Kayıt hatası: $e');
    }
  }

  Future<void> stopRecording() async {
    try {
      await _channel.invokeMethod('stopRecording');
    } catch (e) {
      print('stopRecording hatası: $e');
    }
  }

  /// Kaydedilmiş WAV dosyasını TFLite modeliyle sınıflandırır.
  Future<Map<String, dynamic>> classifyFile(String filePath) async {
    try {
      final result = await _channel.invokeMethod<Map>(
        'classifyFile',
        {'filePath': filePath},
      );
      if (result == null) return _error('Sonuç alınamadı');

      // Güven oranını Kotlin'den okuyoruz (0.0 ile 1.0 arası)
      final confidence = (result['confidence'] as num?)?.toDouble() ?? 0.0;

      return {
        'success': true,
        'label': result['label'] ?? 'Bilinmiyor',
        'emoji': result['emoji'] ?? '❓',
        'confidence': confidence,
        'confidencePercent': (confidence * 100).toInt(),
        'allProbabilities': result['allProbabilities'] ?? [],
        'topEmotions': _getTopEmotionsFromResult(result),
      };
    } on PlatformException catch (e) {
      return _error('Sınıflandırma hatası: ${e.message}');
    } catch (e) {
      return _error('Sınıflandırma hatası: $e');
    }
  }

  // Kotlin'den gelen List<double> formatındaki tüm olasılıkları
  // Dart arayüzünün anlayacağı List<Map> formatına çevirir ve en yüksek 3'ünü alır.
  List<Map<String, dynamic>> _getTopEmotionsFromResult(Map result) {
    try {
      final probsList = (result['allProbabilities'] as List?)?.cast<double>() ?? [];
      if (probsList.isEmpty) return [];

      // Modelin çıkış sırasına göre etiketler ve emojiler
      final List<String> labels = ['Mutlu', 'Nötr', 'Üzgün', 'Öfkeli', 'İğrenme', 'Korku', 'Şaşkınlık'];
      final List<String> emojis = ['😊', '😐', '😢', '😡', '🤢', '😨', '😲'];

      final indexed = List.generate(probsList.length, (i) => {
        'idx': i,
        'prob': probsList[i]
      });
      
      // Olasılıkları büyükten küçüğe sırala
      indexed.sort((a, b) => (b['prob'] as double).compareTo(a['prob'] as double));
      
      // Sadece en yüksek 3 olasılığı (Top 3) döndür
      return indexed.take(3).map((e) => {
        'label': labels[e['idx'] as int],
        'emoji': emojis[e['idx'] as int],
        'probability': e['prob'],
      }).toList();
    } catch (e) {
      print('Top emotions parse hatası: $e');
      return [];
    }
  }

  Future<void> releaseModel() async {
    try {
      await _channel.invokeMethod('releaseModel');
    } catch (_) {}
  }

  Future<bool> isModelReady() async {
    try {
      return await _channel.invokeMethod<bool>('isModelReady') ?? false;
    } catch (_) {
      return false;
    }
  }

  Map<String, dynamic> _error(String message) => {
        'success': false,
        'error': message,
        'label': 'Hata',
        'emoji': '❓',
        'confidence': 0.0,
        'confidencePercent': 0,
        'allProbabilities': [],
        'topEmotions': <Map<String, dynamic>>[],
      };
}