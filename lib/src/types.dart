import 'dart:typed_data';

/// Interleaved float PCM.
final class AudioBuffer {
  /// `frames * channels` samples, interleaved.
  final Float32List samples;
  final int sampleRate;
  final int channels;

  AudioBuffer(this.samples, {required this.sampleRate, this.channels = 1})
    : assert(channels > 0),
      assert(samples.length % channels == 0);

  /// Samples per channel.
  int get frames => samples.length ~/ channels;

  Duration get duration =>
      Duration(microseconds: frames * 1000000 ~/ sampleRate);

  @override
  String toString() =>
      'AudioBuffer($frames frames, $sampleRate Hz, $channels ch)';
}

/// Kinds of opaque payloads a family produces or consumes.
enum ArtifactKind {
  speakerEmbedding,
  styleEmbedding,
  promptEmbedding,
  acousticTokens,
  midi,
  transcriptAlignment,
  diarizationState,
  vadState,
  custom,
}

/// A speaker embedding, acoustic tokens, MIDI, ... Feed one from a result
/// back into a later request to reuse voice state without re-deriving it.
final class Artifact {
  final ArtifactKind kind;
  final String id;
  final Uint8List payload;
  final Map<String, String> meta;

  const Artifact({
    required this.kind,
    required this.payload,
    this.id = '',
    this.meta = const {},
  });

  @override
  String toString() =>
      'Artifact(${kind.name}, id: "$id", ${payload.length} bytes)';
}

/// A time span, in samples of the input audio.
final class Segment {
  final int startSample;
  final int endSample;
  final double confidence;
  final String text;

  const Segment({
    required this.startSample,
    required this.endSample,
    required this.confidence,
    required this.text,
  });

  @override
  String toString() => 'Segment($startSample-$endSample, "$text")';
}

final class SpeakerTurn {
  final int startSample;
  final int endSample;
  final String speakerId;
  final double confidence;
  final String text;

  const SpeakerTurn({
    required this.startSample,
    required this.endSample,
    required this.speakerId,
    required this.confidence,
    required this.text,
  });

  @override
  String toString() => 'SpeakerTurn($speakerId, $startSample-$endSample)';
}

final class Word {
  final String word;
  final int startSample;
  final int endSample;
  final double confidence;

  const Word({
    required this.word,
    required this.startSample,
    required this.endSample,
    required this.confidence,
  });

  @override
  String toString() => 'Word("$word", $startSample-$endSample)';
}

/// One of several audio outputs (separated stems, multi-speaker TTS).
final class NamedAudio {
  final String id;
  final AudioBuffer audio;

  const NamedAudio(this.id, this.audio);

  @override
  String toString() => 'NamedAudio("$id", $audio)';
}

/// Everything a task produced. A plain Dart copy: it owns no native memory
/// and can be sent between isolates.
final class TaskResult {
  final AudioBuffer? audio;
  final String? text;
  final String? language;
  final List<Segment> segments;
  final List<SpeakerTurn> speakerTurns;
  final List<Word> words;
  final List<NamedAudio> namedAudio;
  final List<Artifact> artifacts;

  const TaskResult({
    this.audio,
    this.text,
    this.language,
    this.segments = const [],
    this.speakerTurns = const [],
    this.words = const [],
    this.namedAudio = const [],
    this.artifacts = const [],
  });

  @override
  String toString() => [
    'TaskResult(',
    if (audio != null) 'audio: $audio, ',
    if (text != null) 'text: "$text", ',
    if (segments.isNotEmpty) 'segments: ${segments.length}, ',
    if (speakerTurns.isNotEmpty) 'speakerTurns: ${speakerTurns.length}, ',
    if (words.isNotEmpty) 'words: ${words.length}, ',
    if (namedAudio.isNotEmpty) 'namedAudio: ${namedAudio.length}, ',
    if (artifacts.isNotEmpty) 'artifacts: ${artifacts.length}',
    ')',
  ].join();
}

enum VoiceActivityKind { speechStart, speechEnd, speechSegment }

final class VoiceActivity {
  final VoiceActivityKind kind;
  final int sample;
  final double probability;

  const VoiceActivity(this.kind, this.sample, this.probability);

  @override
  String toString() => 'VoiceActivity(${kind.name} @ $sample, $probability)';
}

/// One event from a streaming session. Partial text appears as
/// [result]`.text`.
final class StreamEvent {
  final bool isFinal;
  final TaskResult result;
  final List<VoiceActivity> voiceActivity;

  const StreamEvent({
    required this.isFinal,
    required this.result,
    this.voiceActivity = const [],
  });

  @override
  String toString() =>
      'StreamEvent(final: $isFinal, $result, voiceActivity: $voiceActivity)';
}

/// Which option map an option belongs to: `--request-option`,
/// `--session-option` or `--load-option`.
enum OptionScope { request, session, load }

/// An option a model family declares, for discovering what it accepts at
/// runtime. Bounds are hints and are not enforced by the library.
final class ModelOption {
  final OptionScope scope;
  final String name;
  final String valueName;
  final String description;
  final String defaultValue;
  final String minValue;
  final String maxValue;
  final bool required;

  const ModelOption({
    required this.scope,
    required this.name,
    required this.valueName,
    required this.description,
    required this.defaultValue,
    required this.minValue,
    required this.maxValue,
    required this.required,
  });

  @override
  String toString() =>
      'ModelOption(${scope.name}: $name'
      '${defaultValue.isEmpty ? '' : ' = $defaultValue'})';
}

enum StreamInputKind { none, audioChunks }

enum StreamOutputKind { finalResult, pullEvents }

/// How a streaming session wants to be fed.
final class StreamPolicy {
  final StreamInputKind input;
  final StreamOutputKind output;

  /// Frames per [push] the family prefers.
  final int preferredChunkSamples;
  final double preferredChunkSeconds;

  const StreamPolicy({
    required this.input,
    required this.output,
    required this.preferredChunkSamples,
    required this.preferredChunkSeconds,
  });

  @override
  String toString() =>
      'StreamPolicy(${input.name}, ${output.name}, '
      '$preferredChunkSamples samples)';
}

/// Compute backend for a session. [best] lets audio.cpp pick.
enum Backend {
  cpu('cpu'),
  cuda('cuda'),
  hip('hip'),
  vulkan('vulkan'),
  metal('metal'),
  best('best');

  final String nativeName;

  const Backend(this.nativeName);
}

/// Session mode.
enum SessionMode {
  offline('offline'),
  streaming('streaming');

  final String nativeName;

  const SessionMode(this.nativeName);
}
