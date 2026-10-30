import 'dart:typed_data';

import 'package:audio_cpp_dart/audio_cpp_dart.dart';
import 'package:test/test.dart';

void main() {
  test('reads the 16-bit fixture', () {
    final audio = Wav.read('test/fixtures/sample_16k.wav');
    expect(audio.sampleRate, 16000);
    expect(audio.channels, 1);
    expect(audio.frames, greaterThan(16000));
    expect(audio.samples.every((s) => s >= -1 && s <= 1), isTrue);
  });

  for (final float in [false, true]) {
    test('round-trips ${float ? 'float' : 'PCM16'} stereo', () {
      final samples = Float32List.fromList([0, 0.5, -0.5, 0.25, -1, 1]);
      final audio = AudioBuffer(samples, sampleRate: 22050, channels: 2);
      final decoded = Wav.decode(Wav.encode(audio, float: float));
      expect(decoded.sampleRate, 22050);
      expect(decoded.channels, 2);
      expect(decoded.frames, 3);
      for (var i = 0; i < samples.length; i++) {
        expect(decoded.samples[i], closeTo(samples[i], float ? 0 : 1e-4));
      }
    });
  }

  test('rejects non-WAVE data', () {
    expect(() => Wav.decode(Uint8List(64)), throwsFormatException);
  });
}
