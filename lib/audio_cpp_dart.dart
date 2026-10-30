/// Dart bindings for [audio.cpp](https://github.com/0xShug0/audio.cpp):
/// in-process TTS, ASR, VAD, diarization, source separation, voice
/// conversion and more, on ggml.
///
/// ```dart
/// final registry = Registry();
/// final model = await registry.loadModelAsync(
///   'models/kokoro-82m-q8_0.gguf',
///   family: 'kokoro_tts',
/// );
/// final session = model.createSession('tts');
/// final request = Request(text: 'Hello from Dart.', language: 'en-us')
///   ..setOption('voice-id', 'af_heart');
/// final result = await session.runAsync(request);
/// Wav.write('hello.wav', result.audio!);
/// ```
///
/// The native library is provided by this package's build hook; see the
/// README for choosing backends and build modes.
library;

export 'src/audio_cpp.dart'
    show AudioCpp, Closeable, Model, Registry, Request, Session;
export 'src/errors.dart';
export 'src/types.dart';
export 'src/wav.dart';
