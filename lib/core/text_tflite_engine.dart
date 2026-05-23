import 'package:tflite_flutter/tflite_flutter.dart';
import 'nlp_processor.dart';

class TextTfliteEngine {
  static const String _modelPath = 'assets/models/en_iyi_metin_modeli.tflite';

  static const List<String> emotionLabels = [
    'Mutlu', 'Nötr', 'Üzgün', 'Öfkeli', 'İğrenme', 'Korku', 'Şaşkınlık',
  ];

  static const List<String> emotionEmojis = [
    '😊', '😐', '😢', '😡', '🤢', '😨', '😲',
  ];

  Interpreter? _interpreter;
  final NlpProcessor _nlp = NlpProcessor();
  bool _isReady = false;

  bool get isReady => _isReady;

  Future<bool> initialize() async {
    await _nlp.loadVocab();

    // ── Yöntem 1: Flex delegate olmadan dene (model sadece builtin ops kullanıyorsa çalışır)
    // ── Yöntem 2: Hata alırsan modeli yeniden dönüştür (aşağıda açıklandı)
    try {
      final options = InterpreterOptions()..threads = 2;
      _interpreter = await Interpreter.fromAsset(_modelPath, options: options);

      final inputShape = _interpreter!.getInputTensor(0).shape;
      final outputShape = _interpreter!.getOutputTensor(0).shape;
      print('TextTFLite yüklendi — giriş: $inputShape, çıkış: $outputShape');

      _isReady = true;
      return true;
    } catch (e) {
      print('TextTFLite model yüklenemedi: $e');
      _isReady = false;
      return false;
    }
  }

  Future<Map<String, dynamic>> classify(String rawText) async {
    if (!_isReady || _interpreter == null) {
      return _errorResult('Model hazır değil');
    }
    if (rawText.trim().isEmpty) return _errorResult('Metin boş');

    try {
      final inputShape = _interpreter!.getInputTensor(0).shape;
      final seqLen = inputShape[1]; // Modelin tam olarak beklediği uzunluk
      
      // Sequence işlemini direkt modelin beklediği boyuta göre yap
      final sequence = _nlp.process(rawText, seqLen);

      final input = [sequence];
      final output = List.generate(1, (_) => List<double>.filled(7, 0.0));
      // ... (geri kalanı aynı)

      _interpreter!.run(input, output);

      final probs = output[0];
      int maxIdx = 0;
      double maxProb = probs[0];
      for (int i = 1; i < probs.length; i++) {
        if (probs[i] > maxProb) { maxProb = probs[i]; maxIdx = i; }
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
    'success': false, 'error': message, 'label': 'Hata', 'emoji': '❓',
    'confidence': 0.0, 'confidencePercent': 0, 'allProbabilities': {}, 'topEmotions': [],
  };

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _isReady = false;
  }
}