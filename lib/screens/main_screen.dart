import 'package:flutter/material.dart';
import '../services/native_audio_channel.dart';
import '../core/text_tflite_engine.dart';

/// Tek ekran uygulaması.
///
/// Ses kaydı akışı:
///   mikrofon'a dokun → kayıt başlar → istediği kadar konuşur →
///   tekrar dokun → stopRecording() → WAV tamamlanır → classifyFile()
///
/// Metin analizi:
///   TextField'e yaz → "Analiz Et" → TextTFLite classify()
class MainScreen extends StatefulWidget {
  const MainScreen({Key? key}) : super(key: key);

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  // ── Servisler ──────────────────────────────────────────────────────────────
  final TextEditingController _textController = TextEditingController();
  final NativeAudioChannel _audioChannel = NativeAudioChannel();
  final TextTfliteEngine _textEngine = TextTfliteEngine();

  // ── Sonuç durumu ───────────────────────────────────────────────────────────
  String _resultText = 'Henüz analiz yapılmadı.';
  String _resultEmoji = '🧠';
  int _confidencePercent = 0;
  List<Map<String, dynamic>> _topEmotions = [];

  // ── UI durumu ──────────────────────────────────────────────────────────────
  bool _isRecording = false;
  bool _isClassifying = false;
  bool _isAnalyzingText = false;

  // Model hazırlık durumları ayrı takip edilir
  bool _textModelReady = false;
  bool _audioModelReady = false;
  bool _isInitializing = true;

  int _elapsedSeconds = 0;

  // Tek dokunma kilidi — hızlı çift tıklamada çift kayıt başlamasını önler
  bool _micTapLocked = false;

  bool get _isBusy => _isRecording || _isClassifying || _isAnalyzingText;
  bool get _anyModelReady => _textModelReady || _audioModelReady;

  // ── Yaşam döngüsü ──────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _initModels();
  }

  Future<void> _initModels() async {
    setState(() => _isInitializing = true);

    // İki model paralel yüklenir
    final results = await Future.wait([
      _textEngine.initialize(),
      _audioChannel.initializeModel(),
    ]);

    if (!mounted) return;
    setState(() {
      _textModelReady = results[0];
      _audioModelReady = results[1];
      _isInitializing = false;

      if (!_anyModelReady) {
        _resultText = 'Modeller yüklenemedi. Uygulamayı yeniden başlatın.';
        _resultEmoji = '⚠️';
      } else {
        // Hangi modelin yüklendiğini göster
        final loaded = [
          if (_textModelReady) 'Metin',
          if (_audioModelReady) 'Ses',
        ].join(' + ');
        _resultText = '$loaded modeli hazır.';
        _resultEmoji = '✅';
      }
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _textEngine.dispose();
    _audioChannel.releaseModel();
    super.dispose();
  }

  // ── Ses analizi ─────────────────────────────────────────────────────────────

  void _onMicTap() {
    // KİLİT KONTROLÜ
    if (_micTapLocked) return;
    
    if (!_audioModelReady) {
      _showSnack('Ses modeli yüklenemedi');
      return;
    }
    if (_isClassifying || _isAnalyzingText) return;

    // Çift tıklamaları engellemek için kilidi hemen aktif ediyoruz
    _micTapLocked = true;

    if (_isRecording) {
      _stopRecording();
    } else {
      _startRecording();
    }

    // 500 milisaniye sonra kilidi kaldır (Donanımsal çift tıklamaları filtreler)
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        _micTapLocked = false;
      }
    });
  }

  void _startRecording() {
    setState(() {
      _isRecording = true;
      _isClassifying = false;
      _resultText = 'Sizi dinliyorum...';
      _resultEmoji = '🎙️';
      _confidencePercent = 0;
      _topEmotions = [];
      _elapsedSeconds = 0;
    });

    _tickElapsed();

    // startRecording() — stopRecording() çağrılana kadar Future tamamlanmaz
    _audioChannel.startRecording().then((result) {
      if (!mounted) return;

      // Kayıt bitti, _isRecording zaten false (stopRecording'de set edildi)
      if (result['success'] != true) {
        setState(() {
          _isRecording = false;
          _isClassifying = false;
          _resultEmoji = '❌';
          _resultText = 'Kayıt hatası: ${result['error']}';
        });
        return;
      }

      // Dosya hazır → sınıflandır
      _classifyFile(result['filePath'] as String);
    }).catchError((e) {
      if (!mounted) return;
      setState(() {
        _isRecording = false;
        _isClassifying = false;
        _resultEmoji = '❌';
        _resultText = 'Kayıt hatası: $e';
      });
    });
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) return;

    // Önce state güncelle, sonra Kotlin'e sinyal gönder
    setState(() {
      _isRecording = false;
      _isClassifying = true; // Spinner → "Analiz ediliyor"
      _resultText = 'Analiz ediliyor...';
      _resultEmoji = '⏳';
    });

    // Kotlin tarafına durdur sinyali → startRecording Future'ı çözülür
    // → then() içinde _classifyFile() çağrılır
    await _audioChannel.stopRecording();
  }

  Future<void> _classifyFile(String filePath) async {
    // _isClassifying zaten _stopRecording'de true yapıldı
    // Sadece _isRecording'i garantiye al
    if (mounted) {
      setState(() {
        _isClassifying = true;
        _isRecording = false;
      });
    }

    final result = await _audioChannel.classifyFile(filePath);
    if (!mounted) return;

    setState(() {
      _isClassifying = false;
      if (result['success'] == true) {
        _resultEmoji = result['emoji'] ?? '❓';
        _resultText = 'Tespit Edilen Duygu: ${result['label']}';
        _confidencePercent = result['confidencePercent'] ?? 0;
        _topEmotions =
            List<Map<String, dynamic>>.from(result['topEmotions'] ?? []);
      } else {
        _resultEmoji = '❌';
        _resultText =
            'Ses analizi başarısız: ${result['error'] ?? 'Bilinmeyen hata'}';
        _confidencePercent = 0;
        _topEmotions = [];
      }
    });
  }

  void _tickElapsed() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted || !_isRecording) return false;
      setState(() => _elapsedSeconds++);
      return true;
    });
  }

  // ── Metin analizi ───────────────────────────────────────────────────────────

  Future<void> _analyzeText() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    if (_isBusy) return;
    if (!_textModelReady) {
      _showSnack('Metin modeli yüklenemedi');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _isAnalyzingText = true;
      _resultText = 'Metin analiz ediliyor...';
      _resultEmoji = '⏳';
      _confidencePercent = 0;
      _topEmotions = [];
    });

    final result = await _textEngine.classify(text);
    if (!mounted) return;

    setState(() {
      _isAnalyzingText = false;
      if (result['success'] == true) {
        _resultEmoji = result['emoji'] ?? '❓';
        _resultText = 'Tespit Edilen Duygu: ${result['label']}';
        _confidencePercent = result['confidencePercent'] ?? 0;
        _topEmotions =
            List<Map<String, dynamic>>.from(result['topEmotions'] ?? []);
      } else {
        _resultEmoji = '❌';
        _resultText =
            'Metin analizi başarısız: ${result['error'] ?? 'Bilinmeyen hata'}';
        _confidencePercent = 0;
        _topEmotions = [];
      }
    });
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  // ── Arayüz ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Duygu Analizi'),
        backgroundColor: Colors.orange,
        elevation: 0,
        centerTitle: true,
        actions: [
          // Model durum göstergesi
          if (!_isInitializing)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Row(
                children: [
                  _modelDot(_textModelReady, 'M'),
                  const SizedBox(width: 4),
                  _modelDot(_audioModelReady, 'S'),
                ],
              ),
            ),
        ],
      ),
      body:
          _isInitializing
              ? const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.orange),
                    SizedBox(height: 16),
                    Text('Modeller yükleniyor...'),
                  ],
                ),
              )
              : SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildResultCard(),
                      if (_topEmotions.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _buildTopEmotionsRow(),
                      ],
                      const SizedBox(height: 28),
                      _buildTextInput(),
                      const SizedBox(height: 12),
                      _buildAnalyzeTextButton(),
                      const SizedBox(height: 40),
                      _buildMicButton(),
                      const SizedBox(height: 16),
                      _buildStatusText(),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
    );
  }

  /// AppBar'daki küçük model durum noktaları (yeşil = hazır, kırmızı = hata)
  Widget _modelDot(bool ready, String label) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: ready ? Colors.greenAccent : Colors.redAccent,
            shape: BoxShape.circle,
          ),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 9, color: Colors.white),
        ),
      ],
    );
  }

  Widget _buildResultCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.orange[100],
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.orange.withOpacity(0.5), width: 2),
      ),
      child: Column(
        children: [
          (_isClassifying || _isAnalyzingText)
              ? const SizedBox(
                width: 60,
                height: 60,
                child: CircularProgressIndicator(
                  color: Colors.orange,
                  strokeWidth: 3,
                ),
              )
              : Text(_resultEmoji, style: const TextStyle(fontSize: 60)),
          const SizedBox(height: 12),
          Text(
            _resultText,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          if (_confidencePercent > 0) ...[
            const SizedBox(height: 8),
            Text(
              'Güven: %$_confidencePercent',
              style: TextStyle(fontSize: 13, color: Colors.orange[800]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTopEmotionsRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children:
          _topEmotions.map((e) {
            final prob = ((e['probability'] as double) * 100).toInt();
            return Column(
              children: [
                Text(
                  e['emoji'] ?? '',
                  style: const TextStyle(fontSize: 22),
                ),
                Text('${e['label']}', style: const TextStyle(fontSize: 11)),
                Text(
                  '%$prob',
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
              ],
            );
          }).toList(),
    );
  }

  Widget _buildTextInput() {
    return TextField(
      controller: _textController,
      maxLines: 4,
      enabled: !_isBusy,
      decoration: InputDecoration(
        hintText:
            'Bugün nasıl hissediyorsun? '
            'İçinden geçenleri buraya yazabilirsin...',
        hintStyle: TextStyle(color: Colors.grey[400]),
        filled: true,
        fillColor: Colors.white,
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: Colors.orange, width: 2),
          borderRadius: BorderRadius.circular(15),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: Colors.grey[300]!, width: 1),
          borderRadius: BorderRadius.circular(15),
        ),
        disabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: Colors.grey[200]!, width: 1),
          borderRadius: BorderRadius.circular(15),
        ),
      ),
    );
  }

  Widget _buildAnalyzeTextButton() {
    final bool canAnalyze = _textModelReady && !_isBusy;
    return ElevatedButton.icon(
      onPressed: canAnalyze ? _analyzeText : null,
      icon: const Icon(Icons.send, color: Colors.white),
      label: Text(
        _isAnalyzingText
            ? 'Analiz ediliyor...'
            : !_textModelReady
            ? 'Metin modeli yüklenemedi'
            : 'Günlüğü Analiz Et',
        style: const TextStyle(
          fontSize: 16,
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.orange,
        disabledBackgroundColor: Colors.orange[200],
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
        ),
        elevation: 2,
      ),
    );
  }

  Widget _buildMicButton() {
    final Color activeColor =
        !_audioModelReady
            ? Colors.grey[400]!
            : _isClassifying
            ? Colors.grey
            : (_isRecording ? Colors.redAccent : Colors.orange);

    return Center(
      child: GestureDetector(
        onTap: _onMicTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: _isRecording ? 100 : 80,
          height: _isRecording ? 100 : 80,
          decoration: BoxDecoration(
            color: activeColor,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: activeColor.withOpacity(0.4),
                blurRadius: _isRecording ? 25 : 15,
                spreadRadius: _isRecording ? 10 : 5,
              ),
            ],
          ),
          child: Icon(
            _isClassifying
                ? Icons.hourglass_top_rounded
                : _isRecording
                ? Icons.stop_rounded
                : Icons.mic_none_rounded,
            color: Colors.white,
            size: 45,
          ),
        ),
      ),
    );
  }

  Widget _buildStatusText() {
    if (!_audioModelReady && !_isInitializing) {
      return Text(
        '⚠️ Ses modeli yüklenemedi — yalnızca metin analizi kullanılabilir.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.orange[700], fontSize: 13),
      );
    }

    if (_isRecording) {
      return Column(
        children: [
          Text(
            '🔴  $_elapsedSeconds sn  —  durdurmak için dokun',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.redAccent,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 60),
            child: LinearProgressIndicator(
              value: null,
              backgroundColor: Colors.grey[200],
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.redAccent),
              minHeight: 5,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ],
      );
    }

    if (_isClassifying) {
      return Center(
        child: Text(
          'Ses analiz ediliyor...',
          style: TextStyle(color: Colors.grey[600], fontSize: 13),
        ),
      );
    }

    return Text(
      'Ses kaydetmek için mikrofon simgesine dokunun.',
      textAlign: TextAlign.center,
      style: TextStyle(
        color: Colors.grey[600],
        fontWeight: FontWeight.w500,
      ),
    );
  }
}