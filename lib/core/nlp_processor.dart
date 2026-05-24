import 'dart:convert';
import 'package:flutter/services.dart';

/// Metin verilerini TFLite modeli için hazırlayan NLP işleme sınıfı.
///
/// pubspec.yaml'da şu asset path'lerin tanımlı olması gerekir:
///   assets:
///     - assets/vocab/word_index.json
///     - assets/models/en_iyi_metin_modeli.tflite
///     - assets/models/en_iyi_ses_modeli.tflite  ← android/app/src/main/assets/ değil!
///
/// Eğitim aşamasındaki ön işleme adımlarını mobil ortamda birebir uygular:
///   1. Gürültü temizleme (URL, mention, RT, noktalama, rakam)
///   2. Küçük harf dönüşümü (Türkçe I/İ dahil)
///   3. Stop-words filtreleme (olumsuzluk belirteçleri korunur)
///   4. Tokenizasyon
///   5. Kelime → index dönüşümü (OOV = 1)
///   6. Padding / kırpma
class NlpProcessor {
  // pubspec.yaml'daki assets bloğunda tanımlı olmalı
  static const String _vocabPath = 'assets/vocab/word_index.json';

  Map<String, int> _wordIndex = {};
  bool _isLoaded = false;

  // Eğitimde kullanılan stop-words listesiyle tutarlı (olumsuzluklar hariç)
  static const Set<String> _stopWords = {
    'acaba', 'altı', 'ama', 'ancak', 'artık', 'asıl', 'aslında', 'az',
    'ba', 'bazı', 'bazıları', 'belki', 'ben', 'bende', 'beni', 'benim',
    'bir', 'birçok', 'biri', 'birkaç', 'birşey', 'biz', 'bize', 'bizim',
    'bu', 'buna', 'bunda', 'bundan', 'bunu', 'bunun', 'burada', 'bütün',
    'çok', 'çünkü', 'da', 'daha', 'dahi', 'de', 'defa', 'den', 'diye',
    'dört', 'e', 'eğer', 'elbette', 'en', 'gerek', 'gereken', 'gi',
    'gibi', 'göre', 'hala', 'hangi', 'hatta', 'hep', 'hepsi', 'her',
    'herkes', 'herşey', 'hız', 'i', 'için', 'ile', 'ise', 'işte',
    'ı', 'içi', 'içinde', 'içinden', 'içine', 'kadar', 'karşı', 'kendi',
    'ki', 'kim', 'kimse', 'madem', 'mi', 'mı', 'mu', 'mü', 'nasıl',
    'ne', 'neden', 'nerde', 'nerede', 'nereye', 'niye', 'o', 'olan',
    'olarak', 'oluyor', 'on', 'ona', 'ondan', 'onlar', 'onları',
    'onların', 'onu', 'onun', 'orada', 'oysa', 'öyle', 'sanki',
    'şey', 'şeyden', 'şeyi', 'şimdi', 'şu', 'şuna', 'şunda', 'şundan',
    'şunu', 'şunun', 'şurada', 'tabii', 'tamam', 'tane', 'tüm', 'u',
    'üç', 'üzere', 've', 'veya', 'ya', 'yani', 'yapılan', 'yapılmış',
    'yedi', 'yer', 'yine', 'yoksa', 'zaten', 'zira',
    'size', 'onlara', 'benden', 'senden', 'bizden',
    'sizden', 'onlardan', 'benimle', 'seninle', 'onunla',
    // NOT: 'değil', 'yok', 'asla', 'hiç' → eğitimde korundu, burada da yok
  };

  Future<bool> loadVocab() async {
    try {
      final String jsonString = await rootBundle.loadString(_vocabPath);
      final Map<String, dynamic> raw = json.decode(jsonString);
      _wordIndex = raw.map((key, value) => MapEntry(key, value as int));
      _isLoaded = true;
      print('NlpProcessor: ${_wordIndex.length} kelime yüklendi');
      return true;
    } catch (e) {
      print('NlpProcessor vocab yüklenemedi: $e');
      // Vocab yüklenemezse boş sözlükle devam — tüm kelimeler OOV (1) olur
      _wordIndex = {};
      _isLoaded = true; // Çalışmaya devam et, sadece OOV modunda
      return false;
    }
  }

  bool get isLoaded => _isLoaded;

  /// Ham metni → TFLite giriş dizisine dönüştürür.
  List<int> process(String rawText, int targetLength) {
    final cleaned = _cleanText(rawText);
    final tokens = _tokenize(cleaned);
    final filtered = _removeStopWords(tokens);
    final indexed = _toSequence(filtered);
    return _pad(indexed, targetLength);
  }

  // ── Özel adımlar ──────────────────────────────────────────────────────────

  String _cleanText(String text) {
    // Türkçe büyük harf → küçük harf (I → ı, İ → i)
    String result = text.replaceAll('I', 'ı').replaceAll('İ', 'i').toLowerCase();

    result = result.replaceAll(RegExp(r'https?://\S+|www\.\S+'), ''); // URL
    result = result.replaceAll(RegExp(r'@\w+'), ''); // @mention
    result = result.replaceAll(RegExp(r'\brt\b'), ''); // RT
    result = result.replaceAll(RegExp(r'\d+'), ''); // Rakamlar
    result = result.replaceAll(
      RegExp(r'[^a-zçğıöşü\s]'),
      '',
    ); // Türkçe alfabe dışı
    result = result.replaceAll(RegExp(r'\s+'), ' ').trim(); // Fazla boşluk

    return result;
  }

  List<String> _tokenize(String text) =>
      text.split(' ').where((w) => w.isNotEmpty).toList();

  /// Stop-words filtresi — olumsuzluk belirteçleri ('değil', 'yok', 'asla', 'hiç')
  /// eğitimde korunduğu için burada da filtrelenmez.
  List<String> _removeStopWords(List<String> tokens) =>
      tokens.where((w) => !_stopWords.contains(w)).toList();

  /// Kelime → index; bilinmeyen kelimeler için OOV = 1
  List<int> _toSequence(List<String> tokens) =>
      tokens.map((t) => _wordIndex[t] ?? 1).toList();

  /// Sağdan sıfır-padding veya kırpma
  List<int> _pad(List<int> seq, int length) {
    if (seq.length >= length) return seq.take(length).toList();
    final padded = List<int>.filled(length, 0);
    for (int i = 0; i < seq.length; i++) {
      padded[i] = seq[i];
    }
    return padded;
  }
}