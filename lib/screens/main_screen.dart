import 'package:flutter/material.dart';
import '../services/native_audio_channel.dart';
import '../core/text_tflite_engine.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({Key? key}) : super(key: key);

  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final TextEditingController _textController = TextEditingController();
  final NativeAudioChannel _audioChannel = NativeAudioChannel();
  final TextTfliteEngine _textEngine = TextTfliteEngine();

  String _resultText = 'Henüz analiz yapılmadı.';
  String _resultEmoji = '🧠';
  int _confidencePercent = 0;
  List<Map<String, dynamic>> _topEmotions = [];

  bool _isRecording = false;
  bool _isClassifying = false; // sadece sınıflandırma aşaması
  bool _isAnalyzingText = false;
  bool _modelsReady = false;

  // Geçen süre sayacı
  int _elapsedSeconds = 0;

  @override
  void initState() {
    super.initState();
    _initModels();
  }

  Future<void> _initModels() async {
    final textOk = await _textEngine.initialize();
    final audioOk = await _audioChannel.initializeModel();
    setState(() {
      _modelsReady = textOk || audioOk;
      if (!_modelsReady) {
        _resultText = 'Modeller yüklenemedi. Lütfen uygulamayı yeniden başlatın.';
      }
    });
  }

  // ─── Ses Analizi ────────────────────────────────────────────────────────────

  /// Butona basınca: kayıt yoksa başlat, kayıt varsa durdur
  void _onMicTap() {
    if (_isClassifying) return; // sınıflandırma bitene kadar bekle
    if (_isAnalyzingText) return;

    if (_isRecording) {
      _stopAndClassify();
    } else {
      _startRecording();
    }
  }

 void _startRecording() {
    setState(() {
      _isRecording = true;
      _resultText = 'Sizi dinliyorum...';
      _resultEmoji = '🎙️';
      _confidencePercent = 0;
      _topEmotions = [];
      _elapsedSeconds = 0;
    });

    _tickElapsed();

    _audioChannel.startRecording().then((result) {
      if (!mounted) return;

      if (!_isClassifying) {
        setState(() {
          _isRecording = false; 
        });
      }

      if (result['success'] != true) {
        setState(() {
          _isClassifying = false;
          _isRecording = false;
          _resultEmoji = '❌';
          _resultText = 'Kayıt hatası: ${result['error']}';
        });
        return;
      }
      if (!_isClassifying) {
        _classifyFile(result['filePath'] as String);
      }
    });
  }

  void _stopAndClassify() async {
    setState(() {
      _isRecording = false;
      _isClassifying = true;
      _resultText = 'Analiz ediliyor...';
      _resultEmoji = '⏳';
    });
    // Kotlin tarafına durdur sinyali gönder → startRecording Future'ı çözülür
    await _audioChannel.stopRecording();
  }

  void _classifyFile(String filePath) async {
    setState(() {
      _isClassifying = true;
      _resultText = 'Analiz ediliyor...';
      _resultEmoji = '⏳';
    });

    final result = await _audioChannel.classifyFile(filePath);

    if (!mounted) return;
    setState(() {
      _isClassifying = false;
      if (result['success'] == true) {
        _resultEmoji = result['emoji'] ?? '❓';
        _resultText = 'Tespit Edilen Duygu: ${result['label']} ${result['emoji']}';
        _confidencePercent = result['confidencePercent'] ?? 0;
        _topEmotions = List<Map<String, dynamic>>.from(result['topEmotions'] ?? []);
      } else {
        _resultEmoji = '❌';
        _resultText = 'Ses analizi başarısız: ${result['error'] ?? 'Bilinmeyen hata'}';
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

  // ─── Metin Analizi ──────────────────────────────────────────────────────────

  Future<void> _analyzeText() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    if (_isAnalyzingText || _isRecording || _isClassifying) return;

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
        _resultText = 'Tespit Edilen Duygu: ${result['label']} ${result['emoji']}';
        _confidencePercent = result['confidencePercent'] ?? 0;
        _topEmotions = List<Map<String, dynamic>>.from(result['topEmotions'] ?? []);
      } else {
        _resultEmoji = '❌';
        _resultText = 'Analiz başarısız: ${result['error'] ?? 'Bilinmeyen hata'}';
        _confidencePercent = 0;
        _topEmotions = [];
      }
    });
  }

  bool get _isBusy => _isRecording || _isClassifying || _isAnalyzingText;

  @override
  void dispose() {
    _textController.dispose();
    _textEngine.dispose();
    _audioChannel.releaseModel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Duygu Analizi',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.orange,
        elevation: 0,
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [

              // ── Sonuç Kartı ──────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.orange[100],
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: Colors.orange.withOpacity(0.5), width: 2),
                ),
                child: Column(
                  children: [
                    (_isClassifying || _isAnalyzingText)
                        ? const CircularProgressIndicator(color: Colors.orange)
                        : Text(_resultEmoji,
                            style: const TextStyle(fontSize: 60)),
                    const SizedBox(height: 12),
                    Text(
                      _resultText,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87),
                    ),
                    if (_confidencePercent > 0) ...[
                      const SizedBox(height: 8),
                      Text('Güven: %$_confidencePercent',
                          style: TextStyle(
                              fontSize: 13, color: Colors.orange[800])),
                    ],
                  ],
                ),
              ),

              // ── Üst 3 Duygu ─────────────────────────────────────────────
              if (_topEmotions.isNotEmpty) ...[
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: _topEmotions.map((e) {
                    final prob =
                        ((e['probability'] as double) * 100).toInt();
                    return Column(
                      children: [
                        Text(e['emoji'] ?? '',
                            style: const TextStyle(fontSize: 22)),
                        Text('${e['label']}',
                            style: const TextStyle(fontSize: 11)),
                        Text('%$prob',
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey[600])),
                      ],
                    );
                  }).toList(),
                ),
              ],

              const SizedBox(height: 28),

              // ── Metin Giriş ──────────────────────────────────────────────
              TextField(
                controller: _textController,
                maxLines: 4,
                enabled: !_isBusy,
                decoration: InputDecoration(
                  hintText:
                      'Bugün nasıl hissediyorsun? İçinden geçenleri buraya yazabilirsin...',
                  hintStyle: TextStyle(color: Colors.grey[400]),
                  filled: true,
                  fillColor: Colors.white,
                  focusedBorder: OutlineInputBorder(
                    borderSide:
                        const BorderSide(color: Colors.orange, width: 2),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderSide:
                        BorderSide(color: Colors.grey[300]!, width: 1),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  disabledBorder: OutlineInputBorder(
                    borderSide:
                        BorderSide(color: Colors.grey[200]!, width: 1),
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _isBusy ? null : _analyzeText,
                icon: const Icon(Icons.send, color: Colors.white),
                label: Text(
                  _isAnalyzingText ? 'Analiz ediliyor...' : 'Günlüğü Analiz Et',
                  style: const TextStyle(
                      fontSize: 16,
                      color: Colors.white,
                      fontWeight: FontWeight.bold),
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
              ),

              const SizedBox(height: 40),

              // ── Ses Kayıt Butonu ─────────────────────────────────────────
              Center(
                child: GestureDetector(
                  onTap: _isClassifying ? null : _onMicTap,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: _isRecording ? 100 : 80,
                    height: _isRecording ? 100 : 80,
                    decoration: BoxDecoration(
                      color: _isClassifying
                          ? Colors.grey[400]
                          : _isRecording
                              ? Colors.redAccent
                              : Colors.orange,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: (_isRecording
                                  ? Colors.redAccent
                                  : Colors.orange)
                              .withOpacity(0.4),
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
              ),

              const SizedBox(height: 16),

              // ── Durum metni ──────────────────────────────────────────────
              if (_isRecording) ...[
                Center(
                  child: Text(
                    '🔴  $_elapsedSeconds sn  —  durdurmak için dokun',
                    style: const TextStyle(
                        color: Colors.redAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 14),
                  ),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 60),
                  child: LinearProgressIndicator(
                    value: null, // belirsiz — kullanıcı ne zaman durduracak belli değil
                    backgroundColor: Colors.grey[200],
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(Colors.redAccent),
                    minHeight: 5,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ] else if (_isClassifying) ...[
                Center(
                  child: Text(
                    'Ses analiz ediliyor...',
                    style:
                        TextStyle(color: Colors.grey[600], fontSize: 13),
                  ),
                ),
              ] else ...[
                Text(
                  'Ses kaydetmek için mikrofon ikonuna dokunun.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.grey[600], fontWeight: FontWeight.w500),
                ),
              ],

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}