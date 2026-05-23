import 'dart:convert';
import 'package:flutter/services.dart';

/// Metin verilerini TFLite modeli için hazırlayan NLP işleme sınıfı.
/// Eğitim aşamasındaki ön işleme adımlarını (temizleme, tokenizasyon,
/// padding) mobil ortamda yeniden uygular.
class NlpProcessor {
  static const String vocabPath = 'assets/vocab/word_index.json';

  Map<String, int> _wordIndex = {};
  bool _isLoaded = false;

  /// Vocab dosyasını assets'ten yükler
  Future<bool> loadVocab() async {
    try {
      final String jsonString = await rootBundle.loadString(vocabPath);
      final Map<String, dynamic> raw = json.decode(jsonString);
      _wordIndex = raw.map((key, value) => MapEntry(key, value as int));
      _isLoaded = true;
      return true;
    } catch (e) {
      // Vocab dosyası bulunamazsa basit fallback: boş vocab ile devam et
      _isLoaded = true;
      return false;
    }
  }

  bool get isLoaded => _isLoaded;

  /// Ana pipeline: ham metni → TFLite giriş dizisine dönüştürür
  List<int> process(String rawText, int targetLength) {
    final cleaned = _cleanText(rawText);
    final tokens = _tokenize(cleaned);
    final indexed = _textToSequence(tokens);
    return _pad(indexed, targetLength);
  }

  /// Sabit uzunluğa padding (sağdan sıfır ekleme) veya kırpma
  List<int> _pad(List<int> sequence, int targetLength) {
    if (sequence.length >= targetLength) {
      return sequence.take(targetLength).toList();
    }
    final padded = List<int>.filled(targetLength, 0);
    for (int i = 0; i < sequence.length; i++) {
      padded[i] = sequence[i];
    }
    return padded;
  }

  /// Eğitimde uygulanan temizlik adımları:
  /// URL, mention, RT, noktalama, emoji kaldırma → küçük harf
  String _cleanText(String text) {
    // Dart'ın toLowerCase hatasını önlemek için önce Türkçe I/İ harflerini çeviriyoruz
    String result = text
        .replaceAll('I', 'ı')
        .replaceAll('İ', 'i')
        .toLowerCase();
        
    // URL temizle
    result = result.replaceAll(RegExp(r'https?://\S+|www\.\S+'), '');
    // Kullanıcı etiketleri (@mention)
    result = result.replaceAll(RegExp(r'@\w+'), '');
    // RT kalıntısı
    result = result.replaceAll(RegExp(r'\brt\b'), '');
    // Rakamlar
    result = result.replaceAll(RegExp(r'\d+'), '');
    // Türkçe alfabesi dışındaki karakterler
    // (olumsuzluk kelimeleri korunacak, sadece sembolleri temizle)
    result = result.replaceAll(RegExp(r'[^a-zçğıöşü\s]'), '');
    // Fazla boşlukları temizle
    result = result.replaceAll(RegExp(r'\s+'), ' ').trim();

    return result;
  }

  /// Kelime tokenizasyonu — stop-words filtrelemesini atlarız çünkü
  /// eğitimde "değil", "yok" gibi olumsuzluk belirteçleri korunmuştu.
  List<String> _tokenize(String text) {
    return text.split(' ').where((w) => w.isNotEmpty).toList();
  }

  /// Kelime → index dönüşümü. Bilinmeyen kelimeler için OOV index = 1
  List<int> _textToSequence(List<String> tokens) {
    return tokens.map((token) {
      return _wordIndex[token] ?? 1; // 1 = <OOV>
    }).toList();
  }
}