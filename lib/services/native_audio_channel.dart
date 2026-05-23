import 'package:flutter/services.dart';

class NativeAudioChannel {
  static const MethodChannel _channel = MethodChannel('duygu_analizi/audio');

  Future<bool> initializeModel() async {
    try {
      final result = await _channel.invokeMethod<Map>('initializeModel');
      return result?['success'] == true;
    } catch (e) {
      return false;
    }
  }

  /// Kaydı başlatır. Tamamlandığında (kullanıcı durdurursa veya süre bitince)
  /// filePath döner. Flutter tarafı daha sonra classifyFile çağırır.
  Future<Map<String, dynamic>> startRecording() async {
    try {
      final result = await _channel.invokeMethod<Map>('startRecording');
      if (result == null) return _errorResult('Sonuç alınamadı');
      if (result['success'] != true) {
        return _errorResult(result['error'] ?? 'Kayıt başlatılamadı');
      }
      return {
        'success': true,
        'filePath': result['filePath'] as String,
      };
    } on PlatformException catch (e) {
      return _errorResult('Platform hatası: ${e.message}');
    } catch (e) {
      return _errorResult('Kayıt hatası: $e');
    }
  }

  /// Kaydı durdurur. startRecording() Future'ı bu çağrıdan sonra çözülür.
  Future<void> stopRecording() async {
    try {
      await _channel.invokeMethod('stopRecording');
    } catch (_) {}
  }

  /// Kaydedilen WAV dosyasını sınıflandırır.
  Future<Map<String, dynamic>> classifyFile(String filePath) async {
    try {
      final result = await _channel.invokeMethod<Map>(
        'classifyFile',
        {'filePath': filePath},
      );
      if (result == null) return _errorResult('Sonuç alınamadı');

      return {
        'success': true,
        'label': result['emotionLabel'] ?? 'Bilinmiyor',
        'emoji': result['emotionEmoji'] ?? '❓',
        'confidence': (result['confidence'] as double?) ?? 0.0,
        'confidencePercent': result['confidencePercent'] ?? 0,
        'allProbabilities': result['allProbabilities'] ?? {},
        'inferenceTimeMs': result['inferenceTimeMs'] ?? 0,
        'topEmotions': result['topEmotions'] ?? [],
      };
    } on PlatformException catch (e) {
      return _errorResult('Sınıflandırma hatası: ${e.message}');
    } catch (e) {
      return _errorResult('Sınıflandırma hatası: $e');
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

  Map<String, dynamic> _errorResult(String message) => {
    'success': false,
    'error': message,
    'label': 'Hata',
    'emoji': '❓',
    'confidence': 0.0,
    'confidencePercent': 0,
    'allProbabilities': {},
    'topEmotions': [],
  };
}