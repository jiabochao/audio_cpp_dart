import 'dart:io';
import 'dart:typed_data';

import 'package:audio_cpp_dart/audio_cpp_dart.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Model files have to be on disk for audio.cpp, so the bundled assets are
/// copied out of the Flutter asset bundle first.
Future<Directory> extractAssets() async {
  final root = Directory(
    '${(await getApplicationSupportDirectory()).path}/audio_cpp_assets',
  );
  for (final asset in [
    'assets/silero_vad/silero_vad_16k.safetensors',
    'assets/sample_16k.wav',
  ]) {
    final file = File('${root.path}/${asset.substring('assets/'.length)}');
    if (file.existsSync()) continue;
    file.parent.createSync(recursive: true);
    final data = await rootBundle.load(asset);
    file.writeAsBytesSync(data.buffer.asUint8List(), flush: true);
  }
  return root;
}

final class VadReport {
  final String version;
  final String family;
  final AudioBuffer audio;
  final List<Segment> segments;
  final int streamedSegments;
  final Duration elapsed;

  const VadReport({
    required this.version,
    required this.family,
    required this.audio,
    required this.segments,
    required this.streamedSegments,
    required this.elapsed,
  });

  @override
  String toString() {
    final rate = audio.sampleRate;
    final spans = segments
        .map(
          (s) =>
              '${(s.startSample / rate).toStringAsFixed(2)}-'
              '${(s.endSample / rate).toStringAsFixed(2)}s',
        )
        .join(', ');
    return 'audio.cpp $version, $family, ${audio.duration.inMilliseconds} ms '
        'of audio in ${elapsed.inMilliseconds} ms\n'
        'offline: ${segments.length} segments ($spans)\n'
        'streaming: $streamedSegments segments';
  }
}

/// Offline and streaming Silero VAD over the bundled speech clip.
Future<VadReport> runVadDemo() async {
  AudioCpp.checkAbi();
  final assets = await extractAssets();
  final audio = Wav.read('${assets.path}/sample_16k.wav');
  final stopwatch = Stopwatch()..start();

  final registry = Registry();
  final model = await registry.loadModelAsync(
    '${assets.path}/silero_vad',
    family: 'silero_vad',
  );
  final offline = await model.createSessionAsync('vad');
  final request = Request(audio: audio);
  final result = await offline.runAsync(request);

  final streaming = model.createSession('vad', mode: SessionMode.streaming);
  final chunk = streaming.streamPolicy.preferredChunkSamples;
  streaming.startStream();
  for (var start = 0; start < audio.frames; start += chunk) {
    final block = Float32List(chunk);
    final end = (start + chunk).clamp(0, audio.frames);
    block.setRange(0, end - start, audio.samples, start);
    streaming.push(AudioBuffer(block, sampleRate: audio.sampleRate));
    streaming.drainEvents();
  }
  final streamed = streaming.finishStream();

  final report = VadReport(
    version: AudioCpp.buildVersion,
    family: model.family,
    audio: audio,
    segments: result.segments,
    streamedSegments: streamed.segments.length,
    elapsed: stopwatch.elapsed,
  );
  for (final handle in <Closeable>[
    request,
    streaming,
    offline,
    model,
    registry,
  ]) {
    handle.close();
  }
  return report;
}
