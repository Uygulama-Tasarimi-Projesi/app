import 'package:flutter/services.dart';
import 'nlp_processor.dart';

class TextTfliteEngine {
  static const platform = MethodChannel('com.example.duygu_analizi/text_model');

  static const List<String> emotionLabels = [
    'Mutlu', 'Nötr', 'Üzgün', 'Öfkeli', 'İğrenme', 'Korku', 'Şaşkınlık',
  ];

  static const List<String> emotionEmojis = [
    '😊', '😐', '😢', '😡', '🤢', '😨', '😲',
  ];

  final NlpProcessor _nlp = NlpProcessor();
  bool _isReady = false;
  final int _seqLen = 50;

  bool get isReady => _isReady;

  Future<bool> initialize() async {
    final vocabOk = await _nlp.loadVocab();
    if (!vocabOk) {
      print('TextTFLite: vocab yüklenemedi, OOV modunda devam ediliyor');
    }
    
    // Kotlin tarafı init edildiği için burada sadece NLP'nin hazır olduğunu varsayıyoruz
    _isReady = true;
    return true;
  }

  Future<Map<String, dynamic>> classify(String rawText) async {
    if (!_isReady) return _errorResult('Sistem hazır değil');
    if (rawText.trim().isEmpty) return _errorResult('Metin boş');

    try {
      // Dart tarafında metni sayılara çevir (Örn: [14, 52, 1, 0, 0...])
      final sequence = _nlp.process(rawText, _seqLen);

      final List<dynamic> result = await platform.invokeMethod('classifyText', {
        'sequence': sequence,
      });

      // Gelen olasılıkları List<double>'a dönüştür
      final probs = result.cast<double>();
      
      int maxIdx = 0;
      double maxProb = probs[0];
      for (int i = 1; i < probs.length; i++) {
        if (probs[i] > maxProb) { 
          maxProb = probs[i]; 
          maxIdx = i; 
        }
      }

      return {
        'success': true,
        'label': emotionLabels[maxIdx],
        'emoji': emotionEmojis[maxIdx],
        'confidence': maxProb,
        'confidencePercent': (maxProb * 100).toInt(),
        'allProbabilities': Map.fromIterables(emotionLabels, probs),
        'topEmotions': _getTopEmotions(probs, 3),
      };
    } catch (e) {
      print('Method Channel classify hatası: $e');
      return _errorResult('Analiz hatası: $e');
    }
  }

  List<Map<String, dynamic>> _getTopEmotions(List<double> probs, int n) {
    final indexed = List.generate(probs.length, (i) => {'idx': i, 'prob': probs[i]});
    indexed.sort((a, b) => (b['prob'] as double).compareTo(a['prob'] as double));
    return indexed.take(n).map((e) => {
      'label': emotionLabels[e['idx'] as int],
      'emoji': emotionEmojis[e['idx'] as int],
      'probability': e['prob'],
    }).toList();
  }

  Map<String, dynamic> _errorResult(String message) => {
    'success': false,
    'error': message,
    'label': 'Hata',
    'emoji': '❓',
    'confidence': 0.0,
    'confidencePercent': 0,
    'allProbabilities': <String, double>{},
    'topEmotions': <Map<String, dynamic>>[],
  };

  void dispose() {
    _isReady = false;
  }
}