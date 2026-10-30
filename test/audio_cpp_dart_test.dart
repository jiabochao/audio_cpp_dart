// End-to-end tests against the real native library, using Silero VAD and a
// speech clip from the upstream repository (test/fixtures), so no model
// download is needed.

import 'dart:typed_data';

import 'package:audio_cpp_dart/audio_cpp_dart.dart';
import 'package:test/test.dart';

const modelPath = 'test/fixtures/silero_vad';
const audioPath = 'test/fixtures/sample_16k.wav';

void main() {
  late AudioBuffer speech;

  setUpAll(() => speech = Wav.read(audioPath));

  group('AudioCpp', () {
    test('reports a compatible ABI', () {
      AudioCpp.checkAbi();
      expect(AudioCpp.abiVersion >> 16, AudioCpp.bindingsAbiMajor);
      expect(AudioCpp.buildVersion, isNotEmpty);
    });

    test('knows the task vocabulary', () {
      expect(AudioCpp.tasks, containsAll(['vad', 'asr', 'tts']));
      expect(AudioCpp.taskFromSpecName('music'), 'gen');
      expect(AudioCpp.taskFromSpecName('not-a-task'), isNull);
    });
  });

  group('Registry', () {
    late Registry registry;
    setUp(() => registry = Registry());
    tearDown(() => registry.close());

    test('lists families', () {
      expect(registry.families, contains('silero_vad'));
    });

    test('reports an unknown family', () {
      expect(
        () => registry.loadModel(modelPath, family: 'no_such_family'),
        throwsA(
          isA<AudioCppException>()
              .having(
                (e) => e.status,
                'status',
                AudioCppStatus.unsupportedFamily,
              )
              .having((e) => e.message, 'message', isNotEmpty),
        ),
      );
    });

    test('close is idempotent and guards use', () {
      registry.close();
      registry.close();
      expect(registry.isClosed, isTrue);
      expect(() => registry.families, throwsStateError);
    });
  });

  group('Silero VAD', () {
    late Registry registry;
    late Model model;

    setUpAll(() async {
      registry = Registry();
      model = await registry.loadModelAsync(modelPath, family: 'silero_vad');
    });

    tearDownAll(() {
      model.close();
      registry.close();
    });

    test('describes itself', () {
      expect(model.family, 'silero_vad');
      expect(model.supports('vad'), isTrue);
      expect(model.supports('vad', mode: SessionMode.streaming), isTrue);
      expect(model.supports('tts'), isFalse);
      for (final scope in OptionScope.values) {
        for (final option in model.options(scope)) {
          expect(option.scope, scope);
          expect(option.name, isNotEmpty);
        }
      }
      expect(model.languages, isA<List<String>>());
    });

    test('finds speech offline, identically across runs', () async {
      final session = model.createSession('vad', threads: 2);
      addTearDown(session.close);
      expect(session.family, 'silero_vad');
      final request = Request(audio: speech);
      addTearDown(request.close);

      final first = session.run(request);
      expect(first.segments, isNotEmpty);
      for (final s in first.segments) {
        expect(s.startSample, lessThan(s.endSample));
        expect(s.endSample, lessThanOrEqualTo(speech.frames));
      }

      final second = await session.runAsync(request);
      expect(
        [for (final s in second.segments) (s.startSample, s.endSample)],
        [for (final s in first.segments) (s.startSample, s.endSample)],
      );
    });

    test('rejects overlapping calls on one session', () async {
      final session = await model.createSessionAsync('vad', threads: 1);
      addTearDown(session.close);
      final request = Request(audio: speech);
      addTearDown(request.close);
      final pending = session.runAsync(request);
      expect(() => session.run(request), throwsStateError);
      expect(session.close, throwsStateError);
      await pending;
    });

    test('streams', () {
      final session = model.createSession(
        'vad',
        mode: SessionMode.streaming,
        threads: 2,
      );
      addTearDown(session.close);
      final policy = session.streamPolicy;
      final chunk = policy.preferredChunkSamples > 0
          ? policy.preferredChunkSamples
          : 512;

      session.startStream();
      final events = <StreamEvent>[];
      for (var start = 0; start < speech.frames; start += chunk) {
        // Silero wants exactly `chunk` frames per push: zero-pad the tail.
        final block = Float32List(chunk);
        final end = (start + chunk).clamp(0, speech.frames);
        block.setRange(0, end - start, speech.samples, start);
        final event = session.push(
          AudioBuffer(block, sampleRate: speech.sampleRate),
        );
        if (event != null) events.add(event);
        events.addAll(session.drainEvents());
      }
      final result = session.finishStream();
      final activity = [for (final e in events) ...e.voiceActivity];
      expect(
        result.segments.isNotEmpty ||
            activity.isNotEmpty ||
            events.any((e) => e.result.segments.isNotEmpty),
        isTrue,
        reason: 'the clip is speech; the stream should report some of it',
      );
    });

    test('offline session refuses streaming calls', () {
      final session = model.createSession('vad', threads: 1);
      addTearDown(session.close);
      expect(session.startStream, throwsA(isA<AudioCppException>()));
    });

    test('handles survive closing their parents', () {
      final registry = Registry();
      final model = registry.loadModel(modelPath, family: 'silero_vad');
      final session = model.createSession('vad', threads: 1);
      model.close();
      registry.close();
      final request = Request(audio: speech);
      expect(session.run(request).segments, isNotEmpty);
      request.close();
      session.close();
    });
  });

  group('Request', () {
    test('accepts every field', () {
      final request = Request(text: 'hello', language: 'en')
        ..textLanguage = 'en'
        ..setOption('seed', '1')
        ..setOptionList('names', ['a', 'b'])
        ..setOptionList('empty', const [])
        ..speakingRate = 1.1
        ..pitchShift = 0.0
        ..energyScale = 1.0
        ..emotion = 'neutral'
        ..styleLanguage = 'en'
        ..setStyleTag('tone', 'calm')
        ..voiceId = 'voice'
        ..setVoiceAudio(AudioBuffer(Float32List(160), sampleRate: 16000));
      final index = request.addArtifact(
        Artifact(
          kind: ArtifactKind.speakerEmbedding,
          id: 'spk',
          payload: Uint8List.fromList([1, 2, 3]),
          meta: const {'dim': '3'},
        ),
      );
      expect(index, 0);
      request.close();
      expect(() => request.setOption('a', 'b'), throwsStateError);
    });
  });
}
