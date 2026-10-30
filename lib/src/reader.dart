import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'bindings/audiocpp.g.dart';
import 'native.dart';
import 'types.dart';

/// Copies everything out of a borrowed native result.
TaskResult readResult(Pointer<audiocpp_result> result) => using((arena) {
  final samples = arena<Pointer<Float>>();
  final frames = arena<Size>();
  final rate = arena<Int>();
  final channels = arena<Int>();
  final string = arena<Pointer<Char>>();
  final string2 = arena<Pointer<Char>>();
  final start = arena<Int64>();
  final end = arena<Int64>();
  final confidence = arena<Float>();

  AudioBuffer copyAudio() {
    final count = frames.value * channels.value;
    return AudioBuffer(
      Float32List.fromList(
        count == 0 ? const [] : samples.value.asTypedList(count),
      ),
      sampleRate: rate.value,
      channels: channels.value == 0 ? 1 : channels.value,
    );
  }

  AudioBuffer? audio;
  final audioStatus = audiocpp_result_audio(
    result,
    samples,
    frames,
    rate,
    channels,
  );
  if (audioStatus == audiocpp_status.AUDIOCPP_OK) {
    audio = copyAudio();
  } else if (audioStatus != audiocpp_status.AUDIOCPP_ERR_NOT_AVAILABLE) {
    check(audioStatus, 'audiocpp_result_audio');
  }

  String? text;
  String? language;
  final textStatus = audiocpp_result_text(result, string, string2);
  if (textStatus == audiocpp_status.AUDIOCPP_OK) {
    text = string.value.toDartString();
    final lang = string2.value.toDartStringOrNull();
    language = lang == null || lang.isEmpty ? null : lang;
  } else if (textStatus != audiocpp_status.AUDIOCPP_ERR_NOT_AVAILABLE) {
    check(textStatus, 'audiocpp_result_text');
  }

  final segments = [
    for (var i = 0; i < audiocpp_result_segment_count(result); i++)
      () {
        check(
          audiocpp_result_segment(result, i, start, end, confidence, string),
          'audiocpp_result_segment',
        );
        return Segment(
          startSample: start.value,
          endSample: end.value,
          confidence: confidence.value,
          text: string.value.toDartString(),
        );
      }(),
  ];

  final turns = [
    for (var i = 0; i < audiocpp_result_speaker_turn_count(result); i++)
      () {
        check(
          audiocpp_result_speaker_turn(
            result,
            i,
            start,
            end,
            string,
            confidence,
            string2,
          ),
          'audiocpp_result_speaker_turn',
        );
        return SpeakerTurn(
          startSample: start.value,
          endSample: end.value,
          speakerId: string.value.toDartString(),
          confidence: confidence.value,
          text: string2.value.toDartString(),
        );
      }(),
  ];

  final words = [
    for (var i = 0; i < audiocpp_result_word_count(result); i++)
      () {
        check(
          audiocpp_result_word(result, i, string, start, end, confidence),
          'audiocpp_result_word',
        );
        return Word(
          word: string.value.toDartString(),
          startSample: start.value,
          endSample: end.value,
          confidence: confidence.value,
        );
      }(),
  ];

  final named = [
    for (var i = 0; i < audiocpp_result_named_audio_count(result); i++)
      () {
        check(
          audiocpp_result_named_audio(
            result,
            i,
            string,
            samples,
            frames,
            rate,
            channels,
          ),
          'audiocpp_result_named_audio',
        );
        return NamedAudio(string.value.toDartString(), copyAudio());
      }(),
  ];

  final kind = arena<UnsignedInt>();
  final payload = arena<Pointer<Void>>();
  final payloadBytes = arena<Size>();
  final artifacts = [
    for (var i = 0; i < audiocpp_result_artifact_count(result); i++)
      () {
        check(
          audiocpp_result_artifact(
            result,
            i,
            kind,
            string,
            payload,
            payloadBytes,
          ),
          'audiocpp_result_artifact',
        );
        final id = string.value.toDartString();
        final bytes = payloadBytes.value == 0
            ? Uint8List(0)
            : Uint8List.fromList(
                payload.value.cast<Uint8>().asTypedList(payloadBytes.value),
              );
        final meta = <String, String>{};
        for (
          var m = 0;
          m < audiocpp_result_artifact_meta_count(result, i);
          m++
        ) {
          check(
            audiocpp_result_artifact_meta(result, i, m, string, string2),
            'audiocpp_result_artifact_meta',
          );
          meta[string.value.toDartString()] = string2.value.toDartString();
        }
        return Artifact(
          kind: ArtifactKind.values[kind.value],
          id: id,
          payload: bytes,
          meta: meta,
        );
      }(),
  ];

  return TaskResult(
    audio: audio,
    text: text,
    language: language,
    segments: segments,
    speakerTurns: turns,
    words: words,
    namedAudio: named,
    artifacts: artifacts,
  );
});

/// Copies a native stream event; does not free it.
StreamEvent readEvent(Pointer<audiocpp_event> event) => using((arena) {
  final kind = arena<UnsignedInt>();
  final sample = arena<Int64>();
  final probability = arena<Float>();
  final activity = [
    for (var i = 0; i < audiocpp_event_voice_activity_count(event); i++)
      () {
        check(
          audiocpp_event_voice_activity(event, i, kind, sample, probability),
          'audiocpp_event_voice_activity',
        );
        return VoiceActivity(
          VoiceActivityKind.values[kind.value],
          sample.value,
          probability.value,
        );
      }(),
  ];
  return StreamEvent(
    isFinal: audiocpp_event_is_final(event) != 0,
    result: readResult(audiocpp_event_as_result(event)),
    voiceActivity: activity,
  );
});

/// Takes ownership of [event]: copies it, frees it, and returns the copy.
StreamEvent? consumeEvent(Pointer<audiocpp_event> event) {
  if (event == nullptr) return null;
  try {
    return readEvent(event);
  } finally {
    audiocpp_event_free(event);
  }
}

/// Takes ownership of [result]: copies it, frees it, and returns the copy.
TaskResult consumeResult(Pointer<audiocpp_result> result) {
  try {
    return readResult(result);
  } finally {
    audiocpp_result_free(result);
  }
}
