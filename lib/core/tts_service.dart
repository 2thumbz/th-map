import 'package:flutter_tts/flutter_tts.dart';

class TtsService {
  final FlutterTts _tts = FlutterTts();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    await _tts.setLanguage('ko-KR');
    await _tts.setSpeechRate(0.52);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
    _initialized = true;
  }

  Future<void> speak(String text, {bool interrupt = false}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    await initialize();
    if (interrupt) {
      await _tts.stop();
    }
    await _tts.speak(trimmed);
  }

  Future<void> stop() async {
    if (!_initialized) return;
    await _tts.stop();
  }

  Future<void> dispose() async {
    await stop();
  }
}
