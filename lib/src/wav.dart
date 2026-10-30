import 'dart:io';
import 'dart:typed_data';

import 'types.dart';

/// Minimal RIFF/WAVE support: 8/16/24/32-bit integer PCM and 32/64-bit float
/// in, 16-bit PCM or 32-bit float out. Enough to get audio in and out of
/// audio.cpp, which itself only deals in float PCM.
abstract final class Wav {
  static AudioBuffer read(String path) => decode(File(path).readAsBytesSync());

  static AudioBuffer decode(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    String tag(int offset) => String.fromCharCodes(bytes, offset, offset + 4);
    if (bytes.length < 12 || tag(0) != 'RIFF' || tag(8) != 'WAVE') {
      throw const FormatException('Not a RIFF/WAVE file.');
    }
    int? format, channels, sampleRate, bits;
    var offset = 12;
    while (offset + 8 <= bytes.length) {
      final id = tag(offset);
      final size = data.getUint32(offset + 4, Endian.little);
      final body = offset + 8;
      if (id == 'fmt ') {
        format = data.getUint16(body, Endian.little);
        channels = data.getUint16(body + 2, Endian.little);
        sampleRate = data.getUint32(body + 4, Endian.little);
        bits = data.getUint16(body + 14, Endian.little);
        if (format == 0xFFFE && size >= 26) {
          // WAVE_FORMAT_EXTENSIBLE: the subformat GUID starts with the tag.
          format = data.getUint16(body + 24, Endian.little);
        }
      } else if (id == 'data') {
        if (format == null) {
          throw const FormatException('WAVE data chunk before fmt chunk.');
        }
        final end = (body + size).clamp(body, bytes.length);
        return AudioBuffer(
          _decodeSamples(data, body, end, format, bits!),
          sampleRate: sampleRate!,
          channels: channels!,
        );
      }
      offset = body + size + (size & 1);
    }
    throw const FormatException('WAVE file has no data chunk.');
  }

  static Float32List _decodeSamples(
    ByteData data,
    int start,
    int end,
    int format,
    int bits,
  ) {
    final width = bits ~/ 8;
    final count = (end - start) ~/ width;
    final out = Float32List(count);
    for (var i = 0, p = start; i < count; i++, p += width) {
      out[i] = switch ((format, bits)) {
        (1, 8) => (data.getUint8(p) - 128) / 128.0,
        (1, 16) => data.getInt16(p, Endian.little) / 32768.0,
        (1, 24) =>
          ((data.getUint8(p) |
                  (data.getUint8(p + 1) << 8) |
                  (data.getInt8(p + 2) << 16))) /
              8388608.0,
        (1, 32) => data.getInt32(p, Endian.little) / 2147483648.0,
        (3, 32) => data.getFloat32(p, Endian.little),
        (3, 64) => data.getFloat64(p, Endian.little),
        _ => throw FormatException(
          'Unsupported WAVE encoding: format $format, $bits bits.',
        ),
      };
    }
    return out;
  }

  static void write(String path, AudioBuffer audio, {bool float = false}) =>
      File(path).writeAsBytesSync(encode(audio, float: float));

  static Uint8List encode(AudioBuffer audio, {bool float = false}) {
    final width = float ? 4 : 2;
    final dataSize = audio.samples.length * width;
    final data = ByteData(44 + dataSize);
    void tag(int offset, String value) {
      for (var i = 0; i < 4; i++) {
        data.setUint8(offset + i, value.codeUnitAt(i));
      }
    }

    tag(0, 'RIFF');
    data.setUint32(4, 36 + dataSize, Endian.little);
    tag(8, 'WAVE');
    tag(12, 'fmt ');
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, float ? 3 : 1, Endian.little);
    data.setUint16(22, audio.channels, Endian.little);
    data.setUint32(24, audio.sampleRate, Endian.little);
    data.setUint32(
      28,
      audio.sampleRate * audio.channels * width,
      Endian.little,
    );
    data.setUint16(32, audio.channels * width, Endian.little);
    data.setUint16(34, width * 8, Endian.little);
    tag(36, 'data');
    data.setUint32(40, dataSize, Endian.little);
    var p = 44;
    for (final sample in audio.samples) {
      if (float) {
        data.setFloat32(p, sample, Endian.little);
      } else {
        data.setInt16(
          p,
          (sample.clamp(-1.0, 1.0) * 32767).round(),
          Endian.little,
        );
      }
      p += width;
    }
    return data.buffer.asUint8List();
  }
}
