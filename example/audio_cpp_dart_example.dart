// Usage:
//   dart run example/audio_cpp_dart_example.dart vad <model> <input.wav>
//   dart run example/audio_cpp_dart_example.dart asr <model> <input.wav> [family]
//   dart run example/audio_cpp_dart_example.dart tts <model> "<text>" <out.wav> [family] [voice-id]
//
// Try `vad test/fixtures/silero_vad test/fixtures/sample_16k.wav`, which
// needs no download. Other models: see the audio.cpp model catalog.

import 'dart:io';

import 'package:audio_cpp_dart/audio_cpp_dart.dart';

Future<void> main(List<String> args) async {
  if (args.length < 3) {
    stderr.writeln('usage: <vad|asr|tts> <model> <input> ...');
    exitCode = 64;
    return;
  }
  final [task, modelPath, input, ...rest] = args;
  print('audio.cpp ${AudioCpp.buildVersion}');

  final registry = Registry();
  final family = switch (task) {
    'vad' => 'silero_vad',
    'tts' => rest.elementAtOrNull(1),
    _ => rest.elementAtOrNull(0),
  };
  final model = await registry.loadModelAsync(modelPath, family: family);
  print('loaded ${model.family}: ${model.description}');
  final session = await model.createSessionAsync(task, backend: Backend.best);

  final audio = task == 'tts' ? null : Wav.read(input);
  final request = switch (audio) {
    null => Request(
      text: input,
      language: 'en-us',
      options: {
        'voice-id': ?rest.elementAtOrNull(2),
      },
    ),
    final audio => Request(audio: audio),
  };
  final stopwatch = Stopwatch()..start();
  final result = await session.runAsync(request);
  print(
    '${task.toUpperCase()} finished in ${stopwatch.elapsedMilliseconds} ms',
  );

  switch (task) {
    case 'tts':
      final out = rest.elementAtOrNull(0) ?? 'out.wav';
      Wav.write(out, result.audio!);
      print('wrote ${result.audio} to $out');
    case 'asr':
      print(result.text);
    default:
      final rate = audio!.sampleRate;
      for (final s in result.segments) {
        print(
          'speech ${(s.startSample / rate).toStringAsFixed(2)}s - '
          '${(s.endSample / rate).toStringAsFixed(2)}s',
        );
      }
  }

  for (final handle in <Closeable>[request, session, model, registry]) {
    handle.close();
  }
}
